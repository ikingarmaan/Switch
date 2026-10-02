import Cocoa
import SwiftUI
import CoreGraphics
import IOKit.pwr_mgt

public extension Notification.Name {
    static let autoTabSwitchStateDidChange = Notification.Name("SwitchAutoTabSwitchStateDidChange")
    static let autoTabSwitchTick = Notification.Name("SwitchAutoTabSwitchTick")
}

public enum TabSwitchDirection: String, CaseIterable, Identifiable, Sendable {
    case forward = "Next Tab (Forward)"
    case reverse = "Previous Tab (Reverse)"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .forward: return "Next ⇥"
        case .reverse: return "Prev ⇤"
        }
    }
}

public enum TabShortcutStyle: String, CaseIterable, Identifiable, Sendable {
    case controlTab = "Control + Tab (Universal)"
    case commandOptionArrows = "⌘ + ⌥ + Arrow (Chrome / Firefox)"
    case commandShiftBrackets = "⌘ + ⇧ + Bracket (Safari / Terminal)"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .controlTab: return "⌃ Tab"
        case .commandOptionArrows: return "⌘⌥→"
        case .commandShiftBrackets: return "⌘⇧]"
        }
    }
}

public final class AutoTabSwitchService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = AutoTabSwitchService()
    
    @Published public private(set) var isActive: Bool = false
    @Published public var switchInterval: Int = 60 // Default 60 seconds (1 minute)
    @Published public private(set) var remainingSeconds: Int = 60
    @Published public var selectedDuration: Int = 0 // 0 = Indefinite
    @Published public private(set) var remainingDurationSeconds: Int = 0
    @Published public var keepAwake: Bool = true
    @Published public var playSound: Bool = false
    @Published public var direction: TabSwitchDirection = .forward
    @Published public var shortcutStyle: TabShortcutStyle = .controlTab
    @Published public private(set) var switchCount: Int = 0
    
    public let intervalPresets: [(seconds: Int, label: String)] = [
        (10, "10s"),
        (15, "15s"),
        (30, "30s"),
        (60, "1m (Default)"),
        (120, "2m"),
        (300, "5m"),
        (600, "10m")
    ]
    
    public let durationPresets: [(seconds: Int, label: String)] = [
        (0, "Indefinite"),
        (900, "15m"),
        (1800, "30m"),
        (3600, "1h"),
        (7200, "2h")
    ]
    
    private var tickerTimer: Timer?
    private var targetEndTime: Date?
    private var displayAssertionID: IOPMAssertionID = 0
    private let lock = NSLock()
    
    // UserDefaults Keys
    private let keyInterval = "switch_auto_tab_interval"
    private let keyDuration = "switch_auto_tab_duration"
    private let keyKeepAwake = "switch_auto_tab_keep_awake"
    private let keyPlaySound = "switch_auto_tab_play_sound"
    private let keyDirection = "switch_auto_tab_direction"
    private let keyShortcutStyle = "switch_auto_tab_shortcut_style"
    
    override private init() {
        super.init()
        
        let savedInterval = UserDefaults.standard.integer(forKey: keyInterval)
        self.switchInterval = savedInterval > 0 ? savedInterval : 60
        self.remainingSeconds = self.switchInterval
        
        self.selectedDuration = UserDefaults.standard.integer(forKey: keyDuration)
        
        if UserDefaults.standard.object(forKey: keyKeepAwake) != nil {
            self.keepAwake = UserDefaults.standard.bool(forKey: keyKeepAwake)
        } else {
            self.keepAwake = true
        }
        
        self.playSound = UserDefaults.standard.bool(forKey: keyPlaySound)
        
        if let dirRaw = UserDefaults.standard.string(forKey: keyDirection),
           let dir = TabSwitchDirection(rawValue: dirRaw) {
            self.direction = dir
        }
        
        if let styleRaw = UserDefaults.standard.string(forKey: keyShortcutStyle),
           let style = TabShortcutStyle(rawValue: styleRaw) {
            self.shortcutStyle = style
        }
    }
    
    public var statusSubtitle: String {
        if !isActive {
            return formattedInterval
        }
        
        if remainingSeconds > 60 {
            let m = remainingSeconds / 60
            let s = remainingSeconds % 60
            return s > 0 ? "in \(m)m \(s)s" : "in \(m)m"
        } else {
            return "in \(remainingSeconds)s"
        }
    }
    
    public var formattedInterval: String {
        if switchInterval >= 60 {
            let m = switchInterval / 60
            let s = switchInterval % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        } else {
            return "\(switchInterval)s"
        }
    }
    
    public func setInterval(_ seconds: Int) {
        self.switchInterval = max(3, seconds)
        UserDefaults.standard.set(self.switchInterval, forKey: keyInterval)
        if !isActive {
            self.remainingSeconds = self.switchInterval
        } else {
            self.remainingSeconds = min(self.remainingSeconds, self.switchInterval)
        }
        notifyChange()
        notifyTick()
    }
    
    public func setDuration(_ seconds: Int) {
        self.selectedDuration = seconds
        UserDefaults.standard.set(seconds, forKey: keyDuration)
        if !isActive {
            self.remainingDurationSeconds = seconds
        } else if seconds > 0 {
            self.remainingDurationSeconds = seconds
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            self.targetEndTime = nil
        }
        notifyChange()
    }
    
    public func setDirection(_ newDirection: TabSwitchDirection) {
        self.direction = newDirection
        UserDefaults.standard.set(newDirection.rawValue, forKey: keyDirection)
        notifyChange()
    }
    
    public func setShortcutStyle(_ newStyle: TabShortcutStyle) {
        self.shortcutStyle = newStyle
        UserDefaults.standard.set(newStyle.rawValue, forKey: keyShortcutStyle)
        notifyChange()
    }
    
    public func setKeepAwake(_ awake: Bool) {
        self.keepAwake = awake
        UserDefaults.standard.set(awake, forKey: keyKeepAwake)
        if isActive {
            if awake {
                acquireDisplayAssertion()
            } else {
                releaseDisplayAssertion()
            }
        }
        notifyChange()
    }
    
    public func setPlaySound(_ sound: Bool) {
        self.playSound = sound
        UserDefaults.standard.set(sound, forKey: keyPlaySound)
        notifyChange()
    }
    
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
        
        self.remainingSeconds = self.switchInterval
        self.remainingDurationSeconds = selectedDuration
        if selectedDuration > 0 {
            self.targetEndTime = Date().addingTimeInterval(TimeInterval(selectedDuration))
        } else {
            self.targetEndTime = nil
        }
        
        self.switchCount = 0
        self.isActive = true
        
        if keepAwake {
            acquireDisplayAssertion()
        }
        
        startTimerLoop()
        notifyChange()
        notifyTick()
    }
    
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isActive else { return }
        isActive = false
        
        tickerTimer?.invalidate()
        tickerTimer = nil
        targetEndTime = nil
        self.remainingSeconds = self.switchInterval
        
        releaseDisplayAssertion()
        notifyChange()
        notifyTick()
    }
    
    // MARK: - Timer Loop
    
    private func startTimerLoop() {
        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.handleTimerTick()
        }
        RunLoop.main.add(tickerTimer!, forMode: .common)
    }
    
    private func handleTimerTick() {
        guard isActive else { return }
        
        // Check overall session duration if set
        if let target = targetEndTime {
            let diff = Int(ceil(target.timeIntervalSinceNow))
            if diff <= 0 {
                remainingDurationSeconds = 0
                stop()
                NSSound(named: "Glass")?.play()
                return
            } else {
                remainingDurationSeconds = diff
            }
        }
        
        remainingSeconds -= 1
        
        if remainingSeconds <= 0 {
            // Trigger tab switch
            performTabSwitch()
            remainingSeconds = switchInterval
        }
        
        notifyTick()
    }
    
    // MARK: - Tab Switch Execution
    
    public func switchTabNow() {
        performTabSwitch()
        if isActive {
            remainingSeconds = switchInterval
            notifyTick()
        }
    }
    
    private func performTabSwitch() {
        switchCount += 1
        
        let isReverse = (direction == .reverse)
        
        // 1. Synthesize key combination
        let src = CGEventSource(stateID: .combinedSessionState)
        
        switch shortcutStyle {
        case .controlTab:
            // Keycode 48 is kVK_Tab
            let flags: CGEventFlags = isReverse ? [.maskControl, .maskShift] : [.maskControl]
            postKeyEvent(source: src, key: 48, flags: flags)
            
        case .commandOptionArrows:
            // Right Arrow: 124, Left Arrow: 123
            let key: CGKeyCode = isReverse ? 123 : 124
            let flags: CGEventFlags = [.maskCommand, .maskAlternate]
            postKeyEvent(source: src, key: key, flags: flags)
            
        case .commandShiftBrackets:
            // Right Bracket ]: 30, Left Bracket [: 33
            let key: CGKeyCode = isReverse ? 33 : 30
            let flags: CGEventFlags = [.maskCommand, .maskShift]
            postKeyEvent(source: src, key: key, flags: flags)
        }
        
        // 2. Play feedback sound if enabled
        if playSound {
            NSSound(named: "Pop")?.play()
        }
    }
    
    private func postKeyEvent(source: CGEventSource?, key: CGKeyCode, flags: CGEventFlags) {
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Power Assertion
    
    private func acquireDisplayAssertion() {
        guard displayAssertionID == 0 else { return }
        let reason = "Switch Auto Tab Switcher Keep Screen Awake" as CFString
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
    
    // MARK: - Notifications
    
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .autoTabSwitchStateDidChange, object: self.isActive)
        }
    }
    
    private func notifyTick() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .autoTabSwitchTick, object: self.statusSubtitle)
        }
    }
}
