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
    case autoDetect = "Auto (Smart Browser Engine)"
    case controlTab = "Control + Tab (Universal)"
    case commandOptionArrows = "⌘ + ⌥ + Arrow (Chrome / Arc)"
    case commandShiftBrackets = "⌘ + ⇧ + Bracket (Safari / Terminal)"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .autoDetect: return "Auto"
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
    @Published public var shortcutStyle: TabShortcutStyle = .autoDetect
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
    
    // Tracks the most recent non-Switch active app
    private var lastExternalApplication: NSRunningApplication?
    
    // Internal cursor for Arc active space tab cycling
    private var arcCurrentTabIndex: Int = 1
    
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
        
        setupAppObserver()
    }
    
    private func setupAppObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let myBundle = Bundle.main.bundleIdentifier
        if app.bundleIdentifier != myBundle && app.activationPolicy == .regular {
            lastExternalApplication = app
        }
    }
    
    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    public func requestAccessibilityPermission(forcePrompt: Bool = false) {
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted || forcePrompt {
            let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
            let options = [checkOptPrompt: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission"
                alert.informativeText = "Switch uses native browser automation for Arc, Safari, and Chrome.\n\nTo also enable keyboard shortcuts across third-party apps like VS Code, Terminal, and Firefox, please grant Switch Accessibility permissions."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Continue")
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
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
            performTabSwitch(activateTargetIfBackground: false)
            remainingSeconds = switchInterval
        }
        
        notifyTick()
    }
    
    // MARK: - Tab Switch Execution
    
    public func switchTabNow() {
        performTabSwitch(activateTargetIfBackground: true)
        if isActive {
            remainingSeconds = switchInterval
            notifyTick()
        }
    }
    
    private func findTargetApplication() -> NSRunningApplication? {
        let myBundle = Bundle.main.bundleIdentifier
        let frontApp = NSWorkspace.shared.frontmostApplication
        
        // 1. If front app is a regular external app, use it
        if let front = frontApp, front.bundleIdentifier != myBundle && front.activationPolicy == .regular {
            return front
        }
        
        // 2. Otherwise use the last recorded external app
        if let last = lastExternalApplication, !last.isTerminated {
            return last
        }
        
        // 3. Otherwise find any running active browser or editor
        let preferredBrowsers = [
            "company.thebrowser.Browser", // Arc
            "com.apple.Safari",           // Safari
            "com.google.Chrome",          // Chrome
            "com.brave.Browser",          // Brave
            "com.microsoft.edgemac",       // Edge
            "org.mozilla.firefox"         // Firefox
        ]
        
        let running = NSWorkspace.shared.runningApplications
        for pref in preferredBrowsers {
            if let found = running.first(where: { $0.bundleIdentifier == pref && !$0.isTerminated }) {
                return found
            }
        }
        
        return frontApp
    }
    
    private func performTabSwitch(activateTargetIfBackground: Bool = false) {
        switchCount += 1
        let isReverse = (direction == .reverse)
        
        let targetApp = findTargetApplication()
        let bid = targetApp?.bundleIdentifier ?? ""
        let appName = targetApp?.localizedName ?? ""
        
        if activateTargetIfBackground, let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: [])
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Dispatch in background thread to avoid hitching UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var didSwitchWithScript = false
            
            // 1. If using Auto Detect, attempt native AppleScript engines for supported browsers
            if self.shortcutStyle == .autoDetect {
                if bid == "company.thebrowser.Browser" {
                    didSwitchWithScript = self.switchTabInArc(isReverse: isReverse)
                } else if bid == "com.apple.Safari" {
                    didSwitchWithScript = self.switchTabInSafari(isReverse: isReverse)
                } else if bid == "com.google.Chrome" || bid == "com.brave.Browser" || bid == "com.microsoft.edgemac" || bid == "com.operasoftware.Opera" || bid == "com.vivaldi.Vivaldi" {
                    didSwitchWithScript = self.switchTabInChromium(appName: appName, isReverse: isReverse)
                }
            }
            
            // 2. Synthesize keyboard shortcut if not switched via native AppleScript
            if !didSwitchWithScript {
                self.synthesizeKeystroke(targetApp: targetApp, isReverse: isReverse)
            }
            
            // 3. Audio feedback
            if self.playSound {
                DispatchQueue.main.async {
                    NSSound(named: "Pop")?.play()
                }
            }
        }
    }
    
    // MARK: - Native AppleScript Browser Engines
    
    private func switchTabInArc(isReverse: Bool) -> Bool {
        // Step 1: Cycle through active space tabs via AppleScript
        let step = isReverse ? -1 : 1
        self.arcCurrentTabIndex += step
        if self.arcCurrentTabIndex < 1 { self.arcCurrentTabIndex = 20 }
        
        let script = """
        tell application "Arc"
            if (count of windows) > 0 then
                tell front window
                    tell active space
                        set totalTabs to count of tabs
                        if totalTabs > 0 then
                            set targetIdx to \(self.arcCurrentTabIndex)
                            if targetIdx > totalTabs then set targetIdx to 1
                            if targetIdx < 1 then set targetIdx to totalTabs
                            tell tab targetIdx to select
                            return targetIdx
                        end if
                    end tell
                end tell
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let res = appleScript.executeAndReturnError(&error)
            if error == nil, let val = res.stringValue, let idx = Int(val) {
                self.arcCurrentTabIndex = idx
                return true
            }
        }
        
        // Step 2: Fallback to Arc's native vertical tab key combinations:
        // Command + Option + Down (Next) / Command + Option + Up (Prev)
        // Command + Shift + ] (Next) / Command + Shift + [ (Prev)
        let arcApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "company.thebrowser.Browser" })
        let pid = arcApp?.processIdentifier
        
        let arrowCode: CGKeyCode = isReverse ? 126 : 125 // 126 = Up, 125 = Down
        let bracketCode: CGKeyCode = isReverse ? 33 : 30 // 33 = [, 30 = ]
        
        sendKeyCombo(modifiers: [55, 58], key: arrowCode, targetPid: pid)
        sendKeyCombo(modifiers: [55, 56], key: bracketCode, targetPid: pid)
        return true
    }
    
    private func switchTabInSafari(isReverse: Bool) -> Bool {
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                tell front window
                    set totalTabs to count of tabs
                    if totalTabs > 1 then
                        set curIndex to index of current tab
                        if \(isReverse ? "true" : "false") then
                            if curIndex > 1 then
                                set current tab to tab (curIndex - 1)
                            else
                                set current tab to tab totalTabs
                            end if
                        else
                            if curIndex < totalTabs then
                                set current tab to tab (curIndex + 1)
                            else
                                set current tab to tab 1
                            end if
                        end if
                        return "success"
                    end if
                end tell
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            _ = appleScript.executeAndReturnError(&error)
            if error == nil {
                return true
            }
        }
        return false
    }
    
    private func switchTabInChromium(appName: String, isReverse: Bool) -> Bool {
        let safeName = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "\(safeName)"
            if (count of windows) > 0 then
                tell front window
                    set totalTabs to count of tabs
                    if totalTabs > 1 then
                        set curIndex to active tab index
                        if \(isReverse ? "true" : "false") then
                            if curIndex > 1 then
                                set active tab index to (curIndex - 1)
                            else
                                set active tab index to totalTabs
                            end if
                        else
                            if curIndex < totalTabs then
                                set active tab index to (curIndex + 1)
                            else
                                set active tab index to 1
                            end if
                        end if
                        return "success"
                    end if
                end tell
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            _ = appleScript.executeAndReturnError(&error)
            if error == nil {
                return true
            }
        }
        return false
    }
    
    // MARK: - Keystroke Simulation Engine
    
    private func synthesizeKeystroke(targetApp: NSRunningApplication?, isReverse: Bool) {
        let pid = targetApp?.processIdentifier
        let isArc = targetApp?.bundleIdentifier == "company.thebrowser.Browser"
        
        switch shortcutStyle {
        case .autoDetect, .controlTab:
            if isArc {
                // Arc uses Down/Up arrows for vertical tabs
                let arrowKey: CGKeyCode = isReverse ? 126 : 125
                sendKeyCombo(modifiers: [55, 58], key: arrowKey, targetPid: pid)
            } else {
                // Keycode 48 is Tab. Modifier 59 is Control, 56 is Shift
                if isReverse {
                    sendKeyCombo(modifiers: [59, 56], key: 48, targetPid: pid)
                } else {
                    sendKeyCombo(modifiers: [59], key: 48, targetPid: pid)
                }
            }
            
        case .commandOptionArrows:
            if isArc {
                // Arc uses vertical sidebar: 125 Down, 126 Up
                let key: CGKeyCode = isReverse ? 126 : 125
                sendKeyCombo(modifiers: [55, 58], key: key, targetPid: pid)
            } else {
                // Right Arrow: 124, Left Arrow: 123
                let key: CGKeyCode = isReverse ? 123 : 124
                sendKeyCombo(modifiers: [55, 58], key: key, targetPid: pid)
            }
            
        case .commandShiftBrackets:
            // Right Bracket ]: 30, Left Bracket [: 33
            let key: CGKeyCode = isReverse ? 33 : 30
            sendKeyCombo(modifiers: [55, 56], key: key, targetPid: pid)
        }
    }
    
    private func sendKeyCombo(modifiers: [CGKeyCode], key: CGKeyCode, targetPid: pid_t?) {
        let src = CGEventSource(stateID: .combinedSessionState)
        
        var currentFlags: CGEventFlags = []
        for mod in modifiers {
            switch mod {
            case 55: currentFlags.insert(.maskCommand)
            case 56: currentFlags.insert(.maskShift)
            case 58: currentFlags.insert(.maskAlternate)
            case 59: currentFlags.insert(.maskControl)
            default: break
            }
        }
        
        // 1. Modifiers down
        for mod in modifiers {
            if let ev = CGEvent(keyboardEventSource: src, virtualKey: mod, keyDown: true) {
                ev.flags = currentFlags
                ev.post(tap: .cghidEventTap)
                if let pid = targetPid { ev.postToPid(pid) }
            }
        }
        
        Thread.sleep(forTimeInterval: 0.015)
        
        // 2. Action key down
        if let keyDn = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            keyDn.flags = currentFlags
            keyDn.post(tap: .cghidEventTap)
            if let pid = targetPid { keyDn.postToPid(pid) }
        }
        
        Thread.sleep(forTimeInterval: 0.025)
        
        // 3. Action key up
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            keyUp.flags = currentFlags
            keyUp.post(tap: .cghidEventTap)
            if let pid = targetPid { keyUp.postToPid(pid) }
        }
        
        Thread.sleep(forTimeInterval: 0.015)
        
        // 4. Modifiers up
        for mod in modifiers.reversed() {
            if let ev = CGEvent(keyboardEventSource: src, virtualKey: mod, keyDown: false) {
                ev.flags = []
                ev.post(tap: .cghidEventTap)
                if let pid = targetPid { ev.postToPid(pid) }
            }
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
