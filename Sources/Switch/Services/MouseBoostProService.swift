import Foundation
import Cocoa
import SwiftUI
import ApplicationServices
import Combine

public extension Notification.Name {
    static let mouseBoostProStateDidChange = Notification.Name("SwitchMouseBoostProStateDidChange")
    static let mouseBoostProHUDDidChange = Notification.Name("SwitchMouseBoostProHUDDidChange")
}



public enum MouseBoostMiddleClickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case superMenu = "superMenu"
    case closeWindow = "closeWindow"
    case minimizeWindow = "minimizeWindow"
    case toggleMaximize = "toggleMaximize"
    case missionControl = "missionControl"
    case showDesktop = "showDesktop"
    case newTab = "newTab"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .superMenu: return "Open Super Menu HUD"
        case .closeWindow: return "Close Window Under Cursor"
        case .minimizeWindow: return "Minimize Window Under Cursor"
        case .toggleMaximize: return "Zoom / Maximize Window"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .newTab: return "Open New Tab (⌘T)"
        }
    }
}

public enum MouseBoostSideButtonAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case navigateBack = "navigateBack"
    case navigateForward = "navigateForward"
    case switchSpaceLeft = "switchSpaceLeft"
    case switchSpaceRight = "switchSpaceRight"
    case missionControl = "missionControl"
    case showDesktop = "showDesktop"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .navigateBack: return "Navigate Back (⌘[)"
        case .navigateForward: return "Navigate Forward (⌘])"
        case .switchSpaceLeft: return "Switch Space Left (⌃←)"
        case .switchSpaceRight: return "Switch Space Right (⌃→)"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        }
    }
}

public enum MouseBoostScrollSpeed: Double, CaseIterable, Identifiable, Codable, Sendable {
    case normal = 1.0
    case fast = 1.8
    case turbo = 2.8
    case extreme = 4.5
    
    public var id: Double { rawValue }
    
    public var label: String {
        switch self {
        case .normal: return "1.0x (Normal)"
        case .fast: return "1.8x (Fast ⚡️)"
        case .turbo: return "2.8x (Turbo 🚀)"
        case .extreme: return "4.5x (Extreme 🏎)"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .normal: return "1.0x"
        case .fast: return "1.8x"
        case .turbo: return "2.8x"
        case .extreme: return "4.5x"
        }
    }
}

public enum NewFileType: String, CaseIterable, Identifiable, Sendable {
    case markdown = "md"
    case plainText = "txt"
    case python = "py"
    case swift = "swift"
    case json = "json"
    case shell = "sh"
    case html = "html"
    case docx = "docx"
    case xlsx = "xlsx"
    case pptx = "pptx"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .markdown: return "Markdown Document (.md)"
        case .plainText: return "Plain Text File (.txt)"
        case .python: return "Python Script (.py)"
        case .swift: return "Swift Source (.swift)"
        case .json: return "JSON File (.json)"
        case .shell: return "Shell Script (.sh)"
        case .html: return "HTML Document (.html)"
        case .docx: return "Word Document (.docx)"
        case .xlsx: return "Excel Sheet (.xlsx)"
        case .pptx: return "PowerPoint Presentation (.pptx)"
        }
    }
    
    public var icon: String {
        switch self {
        case .markdown: return "doc.richtext"
        case .plainText: return "doc.text"
        case .python: return "curlybraces"
        case .swift: return "swift"
        case .json: return "curlybraces.square"
        case .shell: return "terminal"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .docx: return "doc.fill"
        case .xlsx: return "tablecells"
        case .pptx: return "rectangle.on.rectangle.fill"
        }
    }
    
    public var defaultContent: String {
        switch self {
        case .markdown: return "# Untitled Document\n\nCreated with MouseBoost Pro in Switch.\n"
        case .plainText: return "Created with MouseBoost Pro in Switch.\n"
        case .python: return "#!/usr/bin/env python3\n\"\"\"\nCreated with MouseBoost Pro in Switch.\n\"\"\"\n\ndef main():\n    print(\"Hello World\")\n\nif __name__ == '__main__':\n    main()\n"
        case .swift: return "import Foundation\n\n// Created with MouseBoost Pro in Switch.\nprint(\"Hello from Swift!\")\n"
        case .json: return "{\n  \"name\": \"Untitled\",\n  \"createdAt\": \"\(ISO8601DateFormatter().string(from: Date()))\"\n}\n"
        case .shell: return "#!/usr/bin/env zsh\n# Created with MouseBoost Pro in Switch.\n\necho \"Script initialized\"\n"
        case .html: return "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title>New Page</title>\n</head>\n<body>\n    <h1>Hello World</h1>\n</body>\n</html>\n"
        default: return ""
        }
    }
}

public final class MouseBoostProService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = MouseBoostProService()
    
    // UserDefaults Keys
    private let keyEnabled = "switch.mouseBoostPro.enabled"
    private let keyMiddleClickAction = "switch.mouseBoostPro.middleClickAction"
    private let keyButton4Action = "switch.mouseBoostPro.button4Action"
    private let keyButton5Action = "switch.mouseBoostPro.button5Action"
    private let keyScrollSpeed = "switch.mouseBoostPro.scrollSpeed"
    private let keyInvertScrollWheel = "switch.mouseBoostPro.invertScrollWheel"
    private let keyFinderRightClickTrigger = "switch.mouseBoostPro.finderRightClickTrigger"
    private let keySoundFeedback = "switch.mouseBoostPro.soundFeedback"
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public var middleClickAction: MouseBoostMiddleClickAction = .superMenu {
        didSet { UserDefaults.standard.set(middleClickAction.rawValue, forKey: keyMiddleClickAction) }
    }
    @Published public var button4Action: MouseBoostSideButtonAction = .navigateBack {
        didSet { UserDefaults.standard.set(button4Action.rawValue, forKey: keyButton4Action) }
    }
    @Published public var button5Action: MouseBoostSideButtonAction = .navigateForward {
        didSet { UserDefaults.standard.set(button5Action.rawValue, forKey: keyButton5Action) }
    }
    @Published public var scrollSpeed: MouseBoostScrollSpeed = .fast {
        didSet { UserDefaults.standard.set(scrollSpeed.rawValue, forKey: keyScrollSpeed) }
    }
    @Published public var invertScrollWheel: Bool = false {
        didSet { UserDefaults.standard.set(invertScrollWheel, forKey: keyInvertScrollWheel) }
    }
    @Published public var soundFeedback: Bool = true {
        didSet { UserDefaults.standard.set(soundFeedback, forKey: keySoundFeedback) }
    }
    
    @Published public private(set) var currentFinderPath: String = ""
    @Published public private(set) var isHUDVisible: Bool = false
    
    private var hudPanel: NSPanel?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    public var statusSubtitle: String? {
        if isEnabled {
            return "\(scrollSpeed.shortLabel) Turbo Scroll"
        }
        return nil
    }
    
    private override init() {
        super.init()
        loadSettings()
        if isEnabled {
            startEventTap()
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: keyEnabled)
        
        if let savedMiddle = defaults.string(forKey: keyMiddleClickAction),
           let action = MouseBoostMiddleClickAction(rawValue: savedMiddle) {
            self.middleClickAction = action
        } else {
            self.middleClickAction = .superMenu
        }
        
        if let savedB4 = defaults.string(forKey: keyButton4Action),
           let action = MouseBoostSideButtonAction(rawValue: savedB4) {
            self.button4Action = action
        } else {
            self.button4Action = .navigateBack
        }
        
        if let savedB5 = defaults.string(forKey: keyButton5Action),
           let action = MouseBoostSideButtonAction(rawValue: savedB5) {
            self.button5Action = action
        } else {
            self.button5Action = .navigateForward
        }
        
        if let savedSpeed = defaults.object(forKey: keyScrollSpeed) as? Double,
           let speed = MouseBoostScrollSpeed(rawValue: savedSpeed) {
            self.scrollSpeed = speed
        } else {
            self.scrollSpeed = .fast
        }
        
        if defaults.object(forKey: keyInvertScrollWheel) != nil {
            self.invertScrollWheel = defaults.bool(forKey: keyInvertScrollWheel)
        } else {
            self.invertScrollWheel = false
        }
        
        if defaults.object(forKey: keySoundFeedback) != nil {
            self.soundFeedback = defaults.bool(forKey: keySoundFeedback)
        } else {
            self.soundFeedback = true
        }
    }
    
    // MARK: - Master Toggle
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: keyEnabled)
        
        if enabled {
            startEventTap()
            playChime(name: "Blow")
        } else {
            stopEventTap()
            hideHUD()
        }
        
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: enabled)
    }
    
    public func setMiddleClickAction(_ action: MouseBoostMiddleClickAction) {
        self.middleClickAction = action
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: isEnabled)
    }
    
    public func setButton4Action(_ action: MouseBoostSideButtonAction) {
        self.button4Action = action
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: isEnabled)
    }
    
    public func setButton5Action(_ action: MouseBoostSideButtonAction) {
        self.button5Action = action
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: isEnabled)
    }
    
    public func setScrollSpeed(_ speed: MouseBoostScrollSpeed) {
        self.scrollSpeed = speed
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: isEnabled)
    }
    
    public func setInvertScrollWheel(_ invert: Bool) {
        self.invertScrollWheel = invert
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: isEnabled)
    }
    
    public func setSoundFeedback(_ sound: Bool) {
        self.soundFeedback = sound
        NotificationCenter.default.post(name: .mouseBoostProStateDidChange, object: isEnabled)
    }
    
    public func setExplicitPath(_ path: String) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            self.currentFinderPath = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
        } else {
            self.currentFinderPath = path
        }
    }
    
    @discardableResult
    public func checkAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Global Event Tap for Mouse Hardware Supercharging
    
    private func startEventTap() {
        stopEventTap()
        
        let mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.scrollWheel.rawValue)
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let service = Unmanaged<MouseBoostProService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleMouseEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = nil
        }
    }
    
    private func handleMouseEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passRetained(event) }
        
        let mouseLocation = NSEvent.mouseLocation
        
        // 1. Handle Middle Click & Side Buttons (Other Mouse Down)
        if type == .otherMouseDown {
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            
            // Button 2 is Middle Click (Wheel Click)
            if buttonNumber == 2 {
                DispatchQueue.main.async {
                    self.executeMiddleClickAction(at: mouseLocation)
                }
                return nil // Consume event
            }
            
            // Button 3 is Back (Side Button 4)
            if buttonNumber == 3 {
                DispatchQueue.main.async {
                    self.executeSideButtonAction(self.button4Action)
                }
                return nil
            }
            
            // Button 4 is Forward (Side Button 5)
            if buttonNumber == 4 {
                DispatchQueue.main.async {
                    self.executeSideButtonAction(self.button5Action)
                }
                return nil
            }
        }
        
        // 2. Handle Scroll Wheel Speed Acceleration & Invert
        if type == .scrollWheel {
            var deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            var deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            
            // Only amplify standard mouse wheel clicks (not delicate trackpad continuous momentum unless desired)
            if !isContinuous || scrollSpeed.rawValue > 1.0 {
                let multiplier = scrollSpeed.rawValue
                
                if invertScrollWheel {
                    deltaY = -deltaY
                }
                
                deltaY *= multiplier
                deltaX *= multiplier
                
                event.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: deltaY)
                event.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: deltaX)
                
                let ptDeltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                if ptDeltaY != 0 {
                    let newPtY = Int64(Double(ptDeltaY) * multiplier * (invertScrollWheel ? -1.0 : 1.0))
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: newPtY)
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - Action Execution
    
    public func executeMiddleClickAction(at mouseLocation: NSPoint) {
        switch middleClickAction {
        case .superMenu:
            showSuperHUD(at: mouseLocation)
            
        case .closeWindow:
            closeWindowUnderCursor(at: mouseLocation)
            
        case .minimizeWindow:
            minimizeWindowUnderCursor(at: mouseLocation)
            
        case .toggleMaximize:
            zoomWindowUnderCursor(at: mouseLocation)
            
        case .missionControl:
            triggerMissionControl()
            
        case .showDesktop:
            triggerShowDesktop()
            
        case .newTab:
            simulateKeyboardShortcut(key: 17, flags: .maskCommand) // ⌘T
        }
    }
    
    public func executeSideButtonAction(_ action: MouseBoostSideButtonAction) {
        switch action {
        case .navigateBack:
            simulateKeyboardShortcut(key: 33, flags: .maskCommand) // ⌘[
        case .navigateForward:
            simulateKeyboardShortcut(key: 30, flags: .maskCommand) // ⌘]
        case .switchSpaceLeft:
            simulateKeyboardShortcut(key: 123, flags: .maskControl) // ⌃←
        case .switchSpaceRight:
            simulateKeyboardShortcut(key: 124, flags: .maskControl) // ⌃→
        case .missionControl:
            triggerMissionControl()
        case .showDesktop:
            triggerShowDesktop()
        }
    }
    
    public func triggerMissionControl() {
        Shell.run("open -a 'Mission Control'")
    }
    
    public func triggerShowDesktop() {
        simulateKeyboardShortcut(key: 103, flags: []) // F11
    }
    
    private func simulateKeyboardShortcut(key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = flags
        
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Window Under Cursor Actions
    
    public func closeWindowUnderCursor(at mousePoint: NSPoint) {
        guard let mainScreen = NSScreen.main else { return }
        let screenHeight = mainScreen.frame.height
        let quartzPoint = CGPoint(x: mousePoint.x, y: screenHeight - mousePoint.y)
        
        let sysElement = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysElement, Float(quartzPoint.x), Float(quartzPoint.y), &elementRef) == .success,
           let element = elementRef {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
               let win = winRef {
                var closeBtnRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXCloseButtonAttribute as CFString, &closeBtnRef) == .success,
                   let btn = closeBtnRef {
                    AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
                    playChime(name: "Tink")
                }
            }
        }
    }
    
    public func minimizeWindowUnderCursor(at mousePoint: NSPoint) {
        guard let mainScreen = NSScreen.main else { return }
        let screenHeight = mainScreen.frame.height
        let quartzPoint = CGPoint(x: mousePoint.x, y: screenHeight - mousePoint.y)
        
        let sysElement = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysElement, Float(quartzPoint.x), Float(quartzPoint.y), &elementRef) == .success,
           let element = elementRef {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
               let win = winRef {
                AXUIElementSetAttributeValue(win as! AXUIElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                playChime(name: "Tink")
            }
        }
    }
    
    public func zoomWindowUnderCursor(at mousePoint: NSPoint) {
        guard let mainScreen = NSScreen.main else { return }
        let screenHeight = mainScreen.frame.height
        let quartzPoint = CGPoint(x: mousePoint.x, y: screenHeight - mousePoint.y)
        
        let sysElement = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysElement, Float(quartzPoint.x), Float(quartzPoint.y), &elementRef) == .success,
           let element = elementRef {
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
               let win = winRef {
                var zoomBtnRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXZoomButtonAttribute as CFString, &zoomBtnRef) == .success,
                   let btn = zoomBtnRef {
                    AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
                    playChime(name: "Tink")
                }
            }
        }
    }
    
    // MARK: - Super Menu HUD & Quick Finder Actions
    
    public func showSuperHUD(at mouseLocation: NSPoint? = nil) {
        updateCurrentFinderPath()
        
        let targetLocation = mouseLocation ?? NSEvent.mouseLocation
        
        if hudPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hosting = NSHostingView(rootView: MouseBoostProHUDView())
            panel.contentView = hosting
            self.hudPanel = panel
        }
        
        guard let panel = hudPanel, let screen = NSScreen.main else { return }
        
        let panelW: CGFloat = 440
        let panelH: CGFloat = 500
        
        // Center near cursor
        var posX = targetLocation.x - (panelW / 2)
        var posY = targetLocation.y - (panelH / 2)
        
        posX = max(screen.visibleFrame.minX + 10, min(screen.visibleFrame.maxX - panelW - 10, posX))
        posY = max(screen.visibleFrame.minY + 10, min(screen.visibleFrame.maxY - panelH - 10, posY))
        
        panel.setFrame(NSRect(x: posX, y: posY, width: panelW, height: panelH), display: true)
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        isHUDVisible = true
        NotificationCenter.default.post(name: .mouseBoostProHUDDidChange, object: true)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1.0
        }
        
        playChime(name: "Pop")
    }
    
    public func hideHUD() {
        guard let panel = hudPanel, panel.isVisible else { return }
        isHUDVisible = false
        NotificationCenter.default.post(name: .mouseBoostProHUDDidChange, object: false)
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    public func updateCurrentFinderPath() {
        let script = """
        tell application "Finder"
            set sel to selection
            if (count of sel) > 0 then
                try
                    return POSIX path of (item 1 of sel as alias)
                on error
                    return POSIX path of (target of Finder window 1 as alias)
                end try
            else if exists Finder window 1 then
                return POSIX path of (target of Finder window 1 as alias)
            else
                return POSIX path of (path to desktop folder as alias)
            end if
        end tell
        """
        let (output, success) = Shell.runAppleScript(script)
        if success && !output.isEmpty {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                self.currentFinderPath = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
            } else {
                self.currentFinderPath = path
            }
        } else {
            self.currentFinderPath = NSHomeDirectory() + "/Desktop"
        }
    }
    
    // MARK: - Super Actions (New File, Terminal, Code, Hashes, Copy Path)
    
    public func createNewFile(type: NewFileType, name: String? = nil) {
        updateCurrentFinderPath()
        let dir = currentFinderPath.isEmpty ? (NSHomeDirectory() + "/Desktop") : currentFinderPath
        
        let baseName = name ?? "Untitled"
        let ext = type.rawValue
        var finalURL = URL(fileURLWithPath: dir).appendingPathComponent("\(baseName).\(ext)")
        
        var counter = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: finalURL.path) {
            finalURL = URL(fileURLWithPath: dir).appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }
        
        do {
            try type.defaultContent.write(to: finalURL, atomically: true, encoding: .utf8)
            
            // Reveal in Finder & select it
            let selectScript = """
            tell application "Finder"
                reveal POSIX file "\(finalURL.path)"
                activate
            end tell
            """
            Shell.runAppleScript(selectScript)
            playChime(name: "Glass")
        } catch {
            print("Failed to create file: \(error)")
        }
        
        hideHUD()
    }
    
    public func openInTerminal() {
        updateCurrentFinderPath()
        let dir = currentFinderPath.isEmpty ? (NSHomeDirectory() + "/Desktop") : currentFinderPath
        Shell.run("open -a Terminal \"\(dir)\"")
        hideHUD()
    }
    
    public func openInVSCode() {
        updateCurrentFinderPath()
        let dir = currentFinderPath.isEmpty ? (NSHomeDirectory() + "/Desktop") : currentFinderPath
        Shell.run("open -a 'Visual Studio Code' \"\(dir)\" || code \"\(dir)\"")
        hideHUD()
    }
    
    public func openInCursor() {
        updateCurrentFinderPath()
        let dir = currentFinderPath.isEmpty ? (NSHomeDirectory() + "/Desktop") : currentFinderPath
        Shell.run("open -a Cursor \"\(dir)\" || cursor \"\(dir)\"")
        hideHUD()
    }
    
    public func copyCurrentPath() {
        updateCurrentFinderPath()
        let dir = currentFinderPath.isEmpty ? (NSHomeDirectory() + "/Desktop") : currentFinderPath
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dir, forType: .string)
        playChime(name: "Tink")
        hideHUD()
    }
    
    public func copyURLPath() {
        updateCurrentFinderPath()
        let dir = currentFinderPath.isEmpty ? (NSHomeDirectory() + "/Desktop") : currentFinderPath
        let fileURL = URL(fileURLWithPath: dir).absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fileURL, forType: .string)
        playChime(name: "Tink")
        hideHUD()
    }
    
    public func calculateChecksum(type: String = "sha256") {
        let script = """
        tell application "Finder"
            set sel to selection
            if (count of sel) > 0 then
                return POSIX path of (item 1 of sel as alias)
            else
                return ""
            end if
        end tell
        """
        let (output, success) = Shell.runAppleScript(script)
        if success && !output.isEmpty {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let hash = Shell.run("shasum -a 256 \"\(path)\" | awk '{print $1}'")
            if !hash.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hash, forType: .string)
                playChime(name: "Glass")
            }
        }
        hideHUD()
    }
    
    public func toggleFinderHiddenFiles() {
        let current = Shell.run("defaults read com.apple.Finder AppleShowAllFiles 2>/dev/null")
        let newState = (current == "1" || current.lowercased() == "true") ? "false" : "true"
        Shell.run("defaults write com.apple.Finder AppleShowAllFiles -bool \(newState); killall Finder")
        playChime(name: "Pop")
        hideHUD()
    }
    
    public func compressSelectedInFinder() {
        let script = """
        tell application "Finder"
            set sel to selection
            if (count of sel) > 0 then
                return POSIX path of (item 1 of sel as alias)
            else
                return ""
            end if
        end tell
        """
        let (output, success) = Shell.runAppleScript(script)
        if success && !output.isEmpty {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let zipPath = "\(path).zip"
            Shell.run("zip -r \"\(zipPath)\" \"\(path)\"")
            playChime(name: "Glass")
        }
        hideHUD()
    }
    
    public func triggerAreaScreenshot() {
        hideHUD()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Shell.run("screencapture -i -c")
        }
    }
    
    private func playChime(name: String) {
        guard soundFeedback && AppSettings.shared.playSound else { return }
        NSSound(named: name)?.play()
    }
}
