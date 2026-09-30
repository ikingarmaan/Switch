import Cocoa
import SwiftUI
import IOKit.pwr_mgt
import IOKit.ps

public extension Notification.Name {
    static let amphetamineStateDidChange = Notification.Name("SwitchAmphetamineStateDidChange")
    static let amphetamineTick = Notification.Name("SwitchAmphetamineTick")
}

public final class AmphetamineService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = AmphetamineService()
    
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var remainingSeconds: Int = 3600 // Default 1 hour
    @Published public var selectedDuration: Int = 3600
    
    public let presets: [(seconds: Int, label: String)] = [
        (900, "15m"),
        (1800, "30m"),
        (3600, "1h"),
        (7200, "2h"),
        (10800, "3h"),
        (14400, "4h"),
        (0, "Indefinite")
    ]
    
    private var timer: Timer?
    private var targetEndTime: Date?
    private var assertionID: IOPMAssertionID = 0
    private var caffeinateProcess: Process?
    private var batteryCheckCounter: Int = 0
    private let lock = NSLock()
    
    public var isIndefinite: Bool {
        return selectedDuration == 0
    }
    
    public var formattedRemainingTime: String {
        if isIndefinite {
            return "Active (Indefinite)"
        }
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    public var formattedSelectedDuration: String {
        if selectedDuration == 0 {
            return "Indefinite"
        }
        let minutes = selectedDuration / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMin = minutes % 60
            return remMin > 0 ? "\(hours)h \(remMin)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
    
    override private init() {
        super.init()
        let saved = UserDefaults.standard.integer(forKey: "savedAmphetamineDuration")
        if saved > 0 || UserDefaults.standard.object(forKey: "savedAmphetamineDuration") != nil {
            self.selectedDuration = saved
            self.remainingSeconds = saved
        }
    }
    
    public func setDuration(_ seconds: Int) {
        self.selectedDuration = seconds
        UserDefaults.standard.set(seconds, forKey: "savedAmphetamineDuration")
        if !isActive {
            self.remainingSeconds = seconds
        } else if seconds > 0 {
            self.remainingSeconds = seconds
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            self.targetEndTime = nil
        }
        NotificationCenter.default.post(name: .amphetamineStateDidChange, object: nil)
    }
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            start()
        } else {
            stop()
        }
    }
    
    public func start(duration: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        if let d = duration {
            self.selectedDuration = d
            UserDefaults.standard.set(d, forKey: "savedAmphetamineDuration")
        }
        
        self.remainingSeconds = selectedDuration
        if selectedDuration > 0 {
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        } else {
            self.targetEndTime = nil
        }
        self.isActive = true
        self.batteryCheckCounter = 0
        
        // 1. Apply IOPMAssertion
        acquirePowerAssertion()
        
        // 2. Launch background caffeinate
        startCaffeinate()
        
        // 3. Enable pmset disablesleep (prevents sleep on lid close)
        enableDisableSleep()
        
        // 4. Start timer loop
        startTimerLoop()
        
        NotificationCenter.default.post(name: .amphetamineStateDidChange, object: true)
        NotificationCenter.default.post(name: .amphetamineTick, object: formattedRemainingTime)
    }
    
    public func stop(showFinishedAlert: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        targetEndTime = nil
        remainingSeconds = selectedDuration
        
        // 1. Release IOPM Assertion
        releasePowerAssertion()
        
        // 2. Stop caffeinate process
        stopCaffeinate()
        
        // 3. Revert pmset disablesleep
        revertDisableSleep()
        
        NotificationCenter.default.post(name: .amphetamineStateDidChange, object: false)
        NotificationCenter.default.post(name: .amphetamineTick, object: "")
        
        if showFinishedAlert {
            DispatchQueue.main.async { [weak self] in
                self?.playNotificationSound()
                self?.presentFinishedAlert()
            }
        }
    }
    
    // MARK: - Timer Loop
    
    private func startTimerLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func tick() {
        guard isActive else { return }
        
        // Battery-floor safety check every 30 seconds
        batteryCheckCounter += 1
        if batteryCheckCounter >= 30 {
            batteryCheckCounter = 0
            if isBatteryLow() {
                DispatchQueue.main.async { [weak self] in
                    self?.stop(showFinishedAlert: false)
                    self?.presentBatteryLowAlert()
                }
                return
            }
        }
        
        if !isIndefinite, let target = targetEndTime {
            let diff = Int(ceil(target.timeIntervalSinceNow))
            if diff <= 0 {
                remainingSeconds = 0
                stop(showFinishedAlert: true)
            } else {
                remainingSeconds = diff
                NotificationCenter.default.post(name: .amphetamineTick, object: formattedRemainingTime)
            }
        } else {
            NotificationCenter.default.post(name: .amphetamineTick, object: "Active (Indefinite)")
        }
    }
    
    // MARK: - Power Assertion
    
    private func acquirePowerAssertion() {
        guard assertionID == 0 else { return }
        let reason = "Switch Amphetamine Lid-Awake Session" as CFString
        _ = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
    }
    
    private func releasePowerAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
    
    // MARK: - Background Caffeinate Process
    
    private func startCaffeinate() {
        stopCaffeinate()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = ["-d", "-i", "-m", "-s", "-u"]
        try? proc.run()
        self.caffeinateProcess = proc
    }
    
    private func stopCaffeinate() {
        if let proc = caffeinateProcess, proc.isRunning {
            proc.terminate()
        }
        caffeinateProcess = nil
    }
    
    // MARK: - Closed-Lid Sleep Override (pmset disablesleep)
    
    private func enableDisableSleep() {
        // Try non-interactive sudo first (immediate if sudoers entry exists)
        let check = Shell.run("sudo -n /usr/bin/pmset -a disablesleep 1 2>&1")
        if !check.contains("password is required") {
            return
        }
        
        // If password is required, prompt user once with system authorization sheet
        // This writes /etc/sudoers.d/switch-disablesleep so future toggles are instant and silent
        DispatchQueue.global(qos: .userInitiated).async {
            let user = NSUserName()
            let script = """
            do shell script "echo '\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1' > /etc/sudoers.d/switch-disablesleep && chmod 0440 /etc/sudoers.d/switch-disablesleep && /usr/bin/pmset -a disablesleep 1" with prompt "Switch needs permission to keep your Mac awake with the lid closed." with administrator privileges
            """
            if let appleScript = NSAppleScript(source: script) {
                var errorInfo: NSDictionary?
                appleScript.executeAndReturnError(&errorInfo)
                if let error = errorInfo {
                    print("AppleScript admin permission: \(error)")
                }
            }
        }
    }
    
    private func revertDisableSleep() {
        _ = Shell.run("sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || true")
    }
    
    // MARK: - Low Battery Protection (Safety Net)
    
    private func isBatteryLow() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let capacity = description[kIOPSCurrentCapacityKey as String] as? Int,
               let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
               maxCapacity > 0 {
                let percent = Int((Double(capacity) / Double(maxCapacity)) * 100)
                let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
                
                // If on battery and below 12%, trip safety cutoff
                if !isCharging && percent <= 12 {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Alerts & Sounds
    
    private func playNotificationSound() {
        let soundNames = ["Glass", "Ping", "Hero", "Blow"]
        for name in soundNames {
            if let sound = NSSound(named: name) {
                sound.play()
                return
            }
        }
        NSSound.beep()
    }
    
    @MainActor
    private func presentFinishedAlert() {
        let alert = NSAlert()
        alert.messageText = "☕ Amphetamine Session Finished"
        alert.informativeText = "Your timed keep-awake session has completed. Normal system sleep settings have been restored."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        alert.runModal()
    }
    
    @MainActor
    private func presentBatteryLowAlert() {
        let alert = NSAlert()
        alert.messageText = "⚠️ Low Battery Safety Cutoff"
        alert.informativeText = "Amphetamine session was automatically stopped because your battery dropped below 12% to prevent your Mac from losing power."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        alert.runModal()
    }
}
