import Cocoa
import SwiftUI
import CoreGraphics
import IOKit.pwr_mgt

public extension Notification.Name {
    static let autoScrollStateDidChange = Notification.Name("SwitchAutoScrollStateDidChange")
    static let autoScrollTick = Notification.Name("SwitchAutoScrollTick")
}

public enum ScrollDirection: String, CaseIterable, Identifiable, Sendable {
    case down = "Down"
    case up = "Up"
    
    public var id: String { rawValue }
    
    public var symbol: String {
        switch self {
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        }
    }
}

public enum ScrollMode: String, CaseIterable, Identifiable, Sendable {
    case bounceUpDown = "Bounce (Up & Down)"
    case continuousDown = "Continuous Down"
    case continuousUp = "Continuous Up"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .bounceUpDown: return "Up & Down"
        case .continuousDown: return "Scroll Down"
        case .continuousUp: return "Scroll Up"
        }
    }
    
    public var icon: String {
        switch self {
        case .bounceUpDown: return "arrow.up.and.down"
        case .continuousDown: return "arrow.down"
        case .continuousUp: return "arrow.up"
        }
    }
}

public enum ScrollSpeed: String, CaseIterable, Identifiable, Sendable {
    case slow = "Slow (Gentle)"
    case normal = "Normal (Smooth)"
    case fast = "Fast (Quick Skim)"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }
    
    public var delta: Int32 {
        switch self {
        case .slow: return 3
        case .normal: return 7
        case .fast: return 18
        }
    }
    
    public var interval: TimeInterval {
        switch self {
        case .slow: return 0.065
        case .normal: return 0.045
        case .fast: return 0.035
        }
    }
}

public final class AutoScrollService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = AutoScrollService()
    
    @Published public private(set) var isActive: Bool = false
    @Published public var mode: ScrollMode = .bounceUpDown
    @Published public var speed: ScrollSpeed = .normal
    @Published public var bounceSteps: Int = 50 // Number of scroll ticks before reversing in bounce mode
    @Published public private(set) var currentDirection: ScrollDirection = .down
    @Published public private(set) var currentStep: Int = 0
    @Published public var selectedDuration: Int = 0 // 0 = Indefinite
    @Published public private(set) var remainingSeconds: Int = 0
    
    public let durationPresets: [(seconds: Int, label: String)] = [
        (900, "15m"),
        (1800, "30m"),
        (3600, "1h"),
        (7200, "2h"),
        (0, "Indefinite")
    ]
    
    public let bouncePresets: [(steps: Int, label: String)] = [
        (25, "Short (25 steps)"),
        (50, "Medium (50 steps)"),
        (100, "Long (100 steps)"),
        (200, "Extended (200 steps)")
    ]
    
    private var scrollTimer: Timer?
    private var countdownTimer: Timer?
    private var targetEndTime: Date?
    private var displayAssertionID: IOPMAssertionID = 0
    private let lock = NSLock()
    
    private let keyMode = "switch.autoscroll.mode"
    private let keySpeed = "switch.autoscroll.speed"
    private let keyBounceSteps = "switch.autoscroll.bounceSteps"
    private let keyDuration = "switch.autoscroll.duration"
    
    public var isIndefinite: Bool {
        return selectedDuration == 0
    }
    
    public var statusSubtitle: String {
        if !isActive {
            return "\(mode.shortLabel) • \(speed.shortLabel)"
        }
        
        switch mode {
        case .bounceUpDown:
            let dirSymbol = currentDirection == .down ? "↓" : "↑"
            return "\(dirSymbol) \(currentDirection.rawValue) (\(currentStep)/\(bounceSteps))"
        case .continuousDown:
            return "Scrolling Down ↓"
        case .continuousUp:
            return "Scrolling Up ↑"
        }
    }
    
    override private init() {
        super.init()
        loadPreferences()
    }
    
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        if let savedMode = defaults.string(forKey: keyMode),
           let m = ScrollMode(rawValue: savedMode) {
            self.mode = m
        }
        
        if let savedSpeed = defaults.string(forKey: keySpeed),
           let s = ScrollSpeed(rawValue: savedSpeed) {
            self.speed = s
        }
        
        let savedSteps = defaults.integer(forKey: keyBounceSteps)
        if savedSteps >= 10 {
            self.bounceSteps = savedSteps
        }
        
        let savedDur = defaults.integer(forKey: keyDuration)
        if savedDur > 0 || defaults.object(forKey: keyDuration) != nil {
            self.selectedDuration = savedDur
            self.remainingSeconds = savedDur
        }
    }
    
    // MARK: - Configuration
    
    public func setMode(_ newMode: ScrollMode) {
        self.mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: keyMode)
        self.currentStep = 0
        self.currentDirection = .down
        notifyChange()
    }
    
    public func setSpeed(_ newSpeed: ScrollSpeed) {
        self.speed = newSpeed
        UserDefaults.standard.set(newSpeed.rawValue, forKey: keySpeed)
        if isActive {
            // Restart scroll timer with new interval
            startScrollLoop()
        }
        notifyChange()
    }
    
    public func setBounceSteps(_ steps: Int) {
        self.bounceSteps = max(10, steps)
        UserDefaults.standard.set(bounceSteps, forKey: keyBounceSteps)
        notifyChange()
    }
    
    public func setDuration(_ seconds: Int) {
        self.selectedDuration = seconds
        UserDefaults.standard.set(seconds, forKey: keyDuration)
        if !isActive {
            self.remainingSeconds = seconds
        } else if seconds > 0 {
            self.remainingSeconds = seconds
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            self.targetEndTime = nil
        }
        notifyChange()
    }
    
    // MARK: - Enable / Disable
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            start()
        } else {
            stop()
        }
    }
    
    public func toggle() {
        setEnabled(!isActive)
    }
    
    public func start(duration: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        if let d = duration {
            self.selectedDuration = d
            UserDefaults.standard.set(d, forKey: keyDuration)
        }
        
        self.remainingSeconds = selectedDuration
        if selectedDuration > 0 {
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        } else {
            self.targetEndTime = nil
        }
        
        self.currentStep = 0
        self.currentDirection = .down
        self.isActive = true
        
        acquireDisplayAssertion()
        startScrollLoop()
        startCountdownLoop()
        
        notifyChange()
    }
    
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isActive else { return }
        isActive = false
        
        scrollTimer?.invalidate()
        scrollTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        targetEndTime = nil
        currentStep = 0
        remainingSeconds = selectedDuration
        
        releaseDisplayAssertion()
        notifyChange()
    }
    
    // MARK: - Scroll Loop
    
    private func startScrollLoop() {
        scrollTimer?.invalidate()
        let interval = speed.interval
        scrollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.performScrollTick()
        }
        RunLoop.main.add(scrollTimer!, forMode: .common)
    }
    
    private func performScrollTick() {
        guard isActive else { return }
        
        let dir: ScrollDirection
        switch mode {
        case .continuousDown:
            dir = .down
        case .continuousUp:
            dir = .up
        case .bounceUpDown:
            currentStep += 1
            if currentStep >= bounceSteps {
                currentStep = 0
                currentDirection = (currentDirection == .down) ? .up : .down
                DispatchQueue.main.async { [weak self] in
                    self?.notifyTick()
                }
            }
            dir = currentDirection
        }
        
        // In macOS CGEvent scrollWheel:
        // wheel1 < 0 scrolls DOWN (viewport moves down)
        // wheel1 > 0 scrolls UP (viewport moves up)
        let delta: Int32 = (dir == .down) ? -speed.delta : speed.delta
        
        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Countdown Loop
    
    private func startCountdownLoop() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }
    
    private func tickCountdown() {
        guard isActive else { return }
        
        if !isIndefinite, let target = targetEndTime {
            let diff = Int(ceil(target.timeIntervalSinceNow))
            if diff <= 0 {
                remainingSeconds = 0
                stop()
                NSSound(named: "Glass")?.play()
            } else {
                remainingSeconds = diff
                notifyTick()
            }
        } else {
            notifyTick()
        }
    }
    
    // MARK: - Display Assertion
    
    private func acquireDisplayAssertion() {
        guard displayAssertionID == 0 else { return }
        let reason = "Switch Auto Scroll Keep Screen Awake" as CFString
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
    
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .autoScrollStateDidChange, object: self.isActive)
        }
    }
    
    private func notifyTick() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .autoScrollTick, object: self.statusSubtitle)
        }
    }
}
