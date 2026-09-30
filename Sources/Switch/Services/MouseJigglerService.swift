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
    
    // Configurable Tile Movement (how many tiles / distance the cursor travels per nudge)
    @Published public var movementTiles: Int = 10
    
    public let tilePresets: [(tiles: Int, label: String)] = [
        (2, "2 Tiles (Micro • 6px)"),
        (5, "5 Tiles (Subtle • 15px)"),
        (10, "10 Tiles (Standard • 30px)"),
        (25, "25 Tiles (Medium • 75px)"),
        (50, "50 Tiles (Wide • 150px)"),
        (100, "100 Tiles (Wander • 300px)")
    ]
    
    private var secondTimer: Timer?
    private var jiggleTimer: Timer?
    private var targetEndTime: Date?
    private var displayAssertionID: IOPMAssertionID = 0
    private var jiggleSign: CGFloat = 1.0
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
    
    public var formattedSubtitle: String {
        let dur = isActive ? formattedRemainingTime : formattedSelectedDuration
        return "\(dur) • \(movementTiles) tiles"
    }
    
    override private init() {
        super.init()
        let saved = UserDefaults.standard.integer(forKey: "savedMouseJigglerDuration")
        if saved > 0 || UserDefaults.standard.object(forKey: "savedMouseJigglerDuration") != nil {
            self.selectedDuration = saved
            self.remainingSeconds = saved
        }
        
        let savedTiles = UserDefaults.standard.integer(forKey: "savedMouseJigglerTiles")
        if savedTiles > 0 {
            self.movementTiles = savedTiles
        } else {
            self.movementTiles = 10
        }
    }
    
    public func setMovementTiles(_ tiles: Int) {
        let clamped = max(1, min(200, tiles))
        self.movementTiles = clamped
        UserDefaults.standard.set(clamped, forKey: "savedMouseJigglerTiles")
        NotificationCenter.default.post(name: .mouseJigglerTick, object: formattedSubtitle)
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
        
        // 1 tile = ~4 pixels of cursor travel
        let stepPixels = CGFloat(movementTiles * 4)
        let delta = stepPixels * jiggleSign
        var newX = currentPos.x + delta
        let newY = currentPos.y
        
        // Screen boundary safety: bounce back if approaching screen edge
        if let screen = NSScreen.main {
            let frame = screen.frame
            if newX > frame.maxX - 20 {
                newX = frame.maxX - 20
                jiggleSign = -1.0
            } else if newX < frame.minX + 20 {
                newX = frame.minX + 20
                jiggleSign = 1.0
            }
        }
        
        jiggleSign = -jiggleSign
        
        let newPos = CGPoint(x: newX, y: newY)
        CGWarpMouseCursorPosition(newPos)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    public func testJiggleNow() {
        let currentPos = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation
        let stepPixels = CGFloat(movementTiles * 4)
        let newPos = CGPoint(x: currentPos.x + stepPixels, y: currentPos.y)
        CGWarpMouseCursorPosition(newPos)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            CGWarpMouseCursorPosition(currentPos)
            if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: currentPos, mouseButton: .left) {
                event.post(tap: .cghidEventTap)
            }
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
