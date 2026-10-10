import Cocoa
import Foundation
import IOKit.ps
import CoreGraphics

public extension Notification.Name {
    static let ultraPowerSaveStateDidChange = Notification.Name("SwitchUltraPowerSaveStateDidChange")
}

public final class UltraPowerSaveService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = UltraPowerSaveService()
    
    private let keyActive = "Switch_UltraPowerSave_Active"
    private let keyTargetBrightness = "Switch_UltraPowerSave_TargetBrightness"
    private let keyAutoDarkMode = "Switch_UltraPowerSave_AutoDarkMode"
    private let keyDisplaySleep = "Switch_UltraPowerSave_DisplaySleep"
    private let keySavedBrightness = "Switch_UltraPowerSave_SavedBrightness"
    private let keySavedDisplaySleep = "Switch_UltraPowerSave_SavedDisplaySleep"
    
    @Published public private(set) var isUltraPowerSaveActive: Bool = false
    @Published public private(set) var batteryPercentage: Int = 100
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var powerSourceState: String = "AC Power"
    
    @Published public var targetBrightnessPercent: Int = 30 {
        didSet {
            UserDefaults.standard.set(targetBrightnessPercent, forKey: keyTargetBrightness)
            if isUltraPowerSaveActive {
                applyBrightness(Float(targetBrightnessPercent) / 100.0)
            }
        }
    }
    
    @Published public var autoDarkModeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoDarkModeEnabled, forKey: keyAutoDarkMode)
            if isUltraPowerSaveActive && autoDarkModeEnabled {
                AppearanceService.shared.setDarkMode(true)
            }
        }
    }
    
    @Published public var displaySleepMinutes: Int = 2 {
        didSet {
            UserDefaults.standard.set(displaySleepMinutes, forKey: keyDisplaySleep)
            if isUltraPowerSaveActive {
                applyDisplaySleep(displaySleepMinutes)
            }
        }
    }
    
    private var batteryTimer: Timer?
    
    // DisplayServices function pointers
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var getBrightnessFunc: GetBrightnessFunc?
    private var setBrightnessFunc: SetBrightnessFunc?
    
    public var statusSubtitle: String {
        let chargingSuffix = isCharging ? " ⚡️" : ""
        if isUltraPowerSaveActive {
            return "⚡️ Ultra Eco · 🔋 \(batteryPercentage)%\(chargingSuffix)"
        } else {
            return "🔋 \(batteryPercentage)%\(isCharging ? " (Charging)" : "")"
        }
    }
    
    private override init() {
        super.init()
        
        // Setup DisplayServices dynamic binding
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
                self.getBrightnessFunc = unsafeBitCast(getSym, to: GetBrightnessFunc.self)
            }
            if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
                self.setBrightnessFunc = unsafeBitCast(setSym, to: SetBrightnessFunc.self)
            }
        }
        
        let savedTargetBright = UserDefaults.standard.integer(forKey: keyTargetBrightness)
        self.targetBrightnessPercent = savedTargetBright > 0 ? savedTargetBright : 30
        
        if UserDefaults.standard.object(forKey: keyAutoDarkMode) != nil {
            self.autoDarkModeEnabled = UserDefaults.standard.bool(forKey: keyAutoDarkMode)
        } else {
            self.autoDarkModeEnabled = true
        }
        
        let savedSleep = UserDefaults.standard.integer(forKey: keyDisplaySleep)
        self.displaySleepMinutes = savedSleep > 0 ? savedSleep : 2
        
        updateBatteryInfo()
        startBatteryMonitoring()
        
        let active = UserDefaults.standard.bool(forKey: keyActive)
        self.isUltraPowerSaveActive = active
    }
    
    deinit {
        batteryTimer?.invalidate()
    }
    
    // MARK: - Battery Monitoring
    
    private func startBatteryMonitoring() {
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.updateBatteryInfo()
        }
    }
    
    public func updateBatteryInfo() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            let curCap = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            let pState = desc[kIOPSPowerSourceStateKey as String] as? String ?? "AC Power"
            
            let pct = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100.0) : curCap
            
            DispatchQueue.main.async {
                self.batteryPercentage = min(100, max(0, pct))
                self.isCharging = charging
                self.powerSourceState = pState
            }
            break
        }
    }
    
    // MARK: - Toggle / State Management
    
    public func toggle() {
        setEnabled(!isUltraPowerSaveActive)
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isUltraPowerSaveActive else { return }
        
        isUltraPowerSaveActive = enabled
        UserDefaults.standard.set(enabled, forKey: keyActive)
        
        if enabled {
            activateUltraPowerSave()
        } else {
            deactivateUltraPowerSave()
        }
        
        NotificationCenter.default.post(name: .ultraPowerSaveStateDidChange, object: enabled)
    }
    
    // MARK: - Activation & Deactivation
    
    private func activateUltraPowerSave() {
        // 1. Save and apply Display Brightness
        if let curBrightness = getCurrentBrightness() {
            UserDefaults.standard.set(curBrightness, forKey: keySavedBrightness)
        }
        applyBrightness(Float(targetBrightnessPercent) / 100.0)
        
        // 2. Enable Dark Mode
        if autoDarkModeEnabled {
            AppearanceService.shared.setDarkMode(true)
        }
        
        // 3. Save and reduce display sleep idle timeout
        let currentSleep = getCurrentDisplaySleep()
        UserDefaults.standard.set(currentSleep, forKey: keySavedDisplaySleep)
        
        // 4. Trigger system lowpowermode and display sleep optimization
        enableLowPowerMode(sleepMinutes: displaySleepMinutes)
    }
    
    private func deactivateUltraPowerSave() {
        // 1. Restore previous brightness
        let savedBright = UserDefaults.standard.float(forKey: keySavedBrightness)
        if savedBright > 0.05 {
            applyBrightness(savedBright)
        }
        
        // 2. Restore previous display sleep timeout
        let savedSleep = UserDefaults.standard.integer(forKey: keySavedDisplaySleep)
        let sleepToRestore = savedSleep > 0 ? savedSleep : 10
        
        // 3. Disable lowpowermode
        disableLowPowerMode(sleepMinutes: sleepToRestore)
    }
    
    // MARK: - Display Brightness Handling
    
    public func getCurrentBrightness() -> Float? {
        guard let getFunc = getBrightnessFunc else { return nil }
        var brightness: Float = 0
        let res = getFunc(CGMainDisplayID(), &brightness)
        return res == 0 ? brightness : nil
    }
    
    public func applyBrightness(_ value: Float) {
        guard let setFunc = setBrightnessFunc else { return }
        let clamped = min(1.0, max(0.05, value))
        _ = setFunc(CGMainDisplayID(), clamped)
    }
    
    // MARK: - pmset Low Power Mode Execution
    
    private func getCurrentDisplaySleep() -> Int {
        let output = Shell.run("/usr/bin/pmset -g 2>/dev/null")
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("displaysleep") {
                let parts = trimmed.split(separator: " ").filter { !$0.isEmpty }
                if parts.count >= 2, let minutes = Int(parts[1]) {
                    return minutes
                }
            }
        }
        return 10
    }
    
    private func applyDisplaySleep(_ minutes: Int) {
        _ = Shell.run("sudo -n /usr/bin/pmset -a displaysleep \(minutes) 2>/dev/null || true")
    }
    
    private func enableLowPowerMode(sleepMinutes: Int) {
        // Check if non-interactive sudo works
        let check = Shell.run("sudo -n /usr/bin/pmset -a lowpowermode 1 displaysleep \(sleepMinutes) disksleep 2 2>&1")
        if !check.contains("password is required") {
            return
        }
        
        // Prompt once with macOS authorization dialog to allow seamless low power control
        DispatchQueue.global(qos: .userInitiated).async {
            let user = NSUserName()
            let script = """
            do shell script "echo '\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1, /usr/bin/pmset -a displaysleep *, /usr/bin/pmset -a disksleep *' > /etc/sudoers.d/switch-powersave && chmod 0440 /etc/sudoers.d/switch-powersave && /usr/bin/pmset -a lowpowermode 1 displaysleep \(sleepMinutes) disksleep 2" with prompt "Switch needs permission to enable Ultra Power Saving Mode." with administrator privileges
            """
            if let appleScript = NSAppleScript(source: script) {
                var errorInfo: NSDictionary?
                appleScript.executeAndReturnError(&errorInfo)
                if let error = errorInfo {
                    print("AppleScript low power mode auth: \(error)")
                }
            }
        }
    }
    
    private func disableLowPowerMode(sleepMinutes: Int) {
        _ = Shell.run("sudo -n /usr/bin/pmset -a lowpowermode 0 displaysleep \(sleepMinutes) disksleep 10 2>/dev/null || true")
    }
    
    // MARK: - Open System Battery Settings
    
    public func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            _ = Shell.run("open /System/Library/PreferencePanes/Battery.prefPane 2>/dev/null || open 'x-apple.systempreferences:'")
        }
    }
}
