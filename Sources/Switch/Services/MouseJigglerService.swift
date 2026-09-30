import Cocoa
import SwiftUI
import CoreGraphics
import IOKit.pwr_mgt

public extension Notification.Name {
    static let mouseJigglerStateDidChange = Notification.Name("SwitchMouseJigglerStateDidChange")
    static let mouseJigglerTick = Notification.Name("SwitchMouseJigglerTick")
}

public final class MouseJigglerService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = MouseJigglerService()
    
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var remainingSeconds: Int = 3600 // Default 1 hour
    @Published public var selectedDuration: Int = 3600
    
    public let presets: [(seconds: Int, label: String)] = [
        (900, "15m"),
        (1800, "30m"),
        (3600, "1h"),
        (7200, "2h"),
        (10800, "3h"),
        (0, "Indefinite")
    ]
    
    private var secondTimer: Timer?
    private var jiggleTimer: Timer?
    private var targetEndTime: Date?
    private var displayAssertionID: IOPMAssertionID = 0
    private var jiggleDelta: CGFloat = 2.0
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
        let saved = UserDefaults.standard.integer(forKey: "savedMouseJigglerDuration")
        if saved > 0 || UserDefaults.standard.object(forKey: "savedMouseJigglerDuration") != nil {
            self.selectedDuration = saved
            self.remainingSeconds = saved
        }
    }
    
    public func setDuration(_ seconds: Int) {
        self.selectedDuration = seconds
        UserDefaults.standard.set(seconds, forKey: "savedMouseJigglerDuration")
        if !isActive {
            self.remainingSeconds = seconds
        } else if seconds > 0 {
            self.remainingSeconds = seconds
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            self.targetEndTime = nil
        }
        NotificationCenter.default.post(name: .mouseJigglerStateDidChange, object: nil)
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
            UserDefaults.standard.set(d, forKey: "savedMouseJigglerDuration")
        }
        
        self.remainingSeconds = selectedDuration
        if selectedDuration > 0 {
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        } else {
            self.targetEndTime = nil
        }
        self.isActive = true
        
        // 1. Keep display awake assertion
        acquireDisplayAssertion()
        
        // 2. Start Jiggle Loop (jiggles every 6 seconds)
        startJiggleLoop()
        
        // 3. Start 1-second countdown timer loop
        startCountdownLoop()
        
        NotificationCenter.default.post(name: .mouseJigglerStateDidChange, object: true)
        NotificationCenter.default.post(name: .mouseJigglerTick, object: formattedRemainingTime)
    }
    
    public func stop(showFinishedAlert: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        
        guard isActive else { return }
        isActive = false
        
        secondTimer?.invalidate()
        secondTimer = nil
        jiggleTimer?.invalidate()
        jiggleTimer = nil
        targetEndTime = nil
        remainingSeconds = selectedDuration
        
        releaseDisplayAssertion()
        
        NotificationCenter.default.post(name: .mouseJigglerStateDidChange, object: false)
        NotificationCenter.default.post(name: .mouseJigglerTick, object: "")
        
        if showFinishedAlert {
            DispatchQueue.main.async { [weak self] in
                self?.playNotificationSound()
                self?.presentFinishedAlert()
            }
        }
    }
    
    // MARK: - Jiggle Action
    
    private func startJiggleLoop() {
        jiggleTimer?.invalidate()
        // Nudge mouse every 6 seconds
        jiggleTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.nudgeMouse()
        }
        // Run immediately once
        nudgeMouse()
    }
    
    private func nudgeMouse() {
        guard isActive else { return }
        
        let currentPos = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
        let newX = currentPos.x + jiggleDelta
        let newPos = CGPoint(x: newX, y: currentPos.y)
        
        // Alternate direction (+2px, -2px) so cursor stays in place
        jiggleDelta = -jiggleDelta
        
        CGWarpMouseCursorPosition(newPos)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Countdown Loop
    
    private func startCountdownLoop() {
        secondTimer?.invalidate()
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func tick() {
        guard isActive else { return }
        
        if !isIndefinite, let target = targetEndTime {
            let diff = Int(ceil(target.timeIntervalSinceNow))
            if diff <= 0 {
                remainingSeconds = 0
                stop(showFinishedAlert: true)
            } else {
                remainingSeconds = diff
                NotificationCenter.default.post(name: .mouseJigglerTick, object: formattedRemainingTime)
            }
        } else {
            NotificationCenter.default.post(name: .mouseJigglerTick, object: "Active (Indefinite)")
        }
    }
    
    // MARK: - Display Assertion
    
    private func acquireDisplayAssertion() {
        guard displayAssertionID == 0 else { return }
        let reason = "Switch Auto Mouse Mover Display Keep Awake" as CFString
        _ = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertionID
        )
    }
    
    private func releaseDisplayAssertion() {
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
    }
    
    // MARK: - Sound & Alert
    
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
        alert.messageText = "🖱️ Mouse Mover Session Finished"
        alert.informativeText = "The timed mouse mover session has completed and the screen will now sleep according to system settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        alert.runModal()
    }
}
