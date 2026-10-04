import Foundation
import Cocoa
import SwiftUI
import ApplicationServices
import Combine

public extension Notification.Name {
    static let dockDoorStateDidChange = Notification.Name("SwitchDockDoorStateDidChange")
}

public enum DockDoorCardSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact = "compact"
    case medium = "medium"
    case large = "large"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .compact: return "Compact (180px)"
        case .medium: return "Medium (240px)"
        case .large: return "Large (300px)"
        }
    }
    
    public var width: CGFloat {
        switch self {
        case .compact: return 180
        case .medium: return 240
        case .large: return 300
        }
    }
    
    public var height: CGFloat {
        switch self {
        case .compact: return 120
        case .medium: return 155
        case .large: return 195
        }
    }
}

public enum DockDoorHoverDelay: Double, CaseIterable, Identifiable, Codable, Sendable {
    case instant = 0.1
    case fast = 0.25
    case normal = 0.4
    
    public var id: Double { rawValue }
    
    public var label: String {
        switch self {
        case .instant: return "Instant (0.1s)"
        case .fast: return "Fast (0.25s)"
        case .normal: return "Normal (0.4s)"
        }
    }
}

public enum DockDoorSwitcherShortcut: String, CaseIterable, Identifiable, Codable, Sendable {
    case commandTab = "commandTab"
    case optionTab = "optionTab"
    case both = "both"
    case disabled = "disabled"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .commandTab: return "Command + Tab (⌘⇥)"
        case .optionTab: return "Option + Tab (⌥⇥)"
        case .both: return "Both (⌘⇥ & ⌥⇥)"
        case .disabled: return "Disabled"
        }
    }
}

public struct DockDoorWindowInfo: Identifiable, Sendable {
    public let id: CGWindowID
    public let title: String
    public let pid: pid_t
    public let appName: String
    public let appIcon: NSImage?
    public let bounds: CGRect
    public let isMinimized: Bool
    public let thumbnail: NSImage?
    
    public init(
        id: CGWindowID,
        title: String,
        pid: pid_t,
        appName: String,
        appIcon: NSImage?,
        bounds: CGRect,
        isMinimized: Bool = false,
        thumbnail: NSImage?
    ) {
        self.id = id
        self.title = title
        self.pid = pid
        self.appName = appName
        self.appIcon = appIcon
        self.bounds = bounds
        self.isMinimized = isMinimized
        self.thumbnail = thumbnail
    }
}

public final class DockDoorService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = DockDoorService()
    
    // UserDefaults Keys
    private let keyEnabled = "switch.dockDoor.enabled"
    private let keyHoverDelay = "switch.dockDoor.hoverDelay"
    private let keyCardSize = "switch.dockDoor.cardSize"
    private let keyShowMinimized = "switch.dockDoor.showMinimized"
    private let keyShowActionButtons = "switch.dockDoor.showActionButtons"
    private let keySoundFeedback = "switch.dockDoor.soundFeedback"
    private let keySwitcherShortcut = "switch.dockDoor.switcherShortcut"
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public var hoverDelay: DockDoorHoverDelay = .fast {
        didSet {
            UserDefaults.standard.set(hoverDelay.rawValue, forKey: keyHoverDelay)
        }
    }
    @Published public var cardSize: DockDoorCardSize = .medium {
        didSet {
            UserDefaults.standard.set(cardSize.rawValue, forKey: keyCardSize)
        }
    }
    @Published public var showMinimized: Bool = true {
        didSet {
            UserDefaults.standard.set(showMinimized, forKey: keyShowMinimized)
        }
    }
    @Published public var showActionButtons: Bool = true {
        didSet {
            UserDefaults.standard.set(showActionButtons, forKey: keyShowActionButtons)
        }
    }
    @Published public var soundFeedback: Bool = true {
        didSet {
            UserDefaults.standard.set(soundFeedback, forKey: keySoundFeedback)
        }
    }
    @Published public var switcherShortcut: DockDoorSwitcherShortcut = .both {
        didSet {
            UserDefaults.standard.set(switcherShortcut.rawValue, forKey: keySwitcherShortcut)
        }
    }
    
    // Hover Preview State
    @Published public private(set) var currentHoveredApp: String?
    @Published public private(set) var currentHoveredIcon: NSImage?
    @Published public private(set) var currentWindows: [DockDoorWindowInfo] = []
    
    // Command+Tab / Alt+Tab Switcher HUD State
    @Published public private(set) var isSwitcherActive: Bool = false
    @Published public private(set) var switcherWindows: [DockDoorWindowInfo] = []
    @Published public private(set) var switcherSelectedIndex: Int = 0
    
    public var selectedSwitcherWindow: DockDoorWindowInfo? {
        guard switcherSelectedIndex >= 0 && switcherSelectedIndex < switcherWindows.count else { return nil }
        return switcherWindows[switcherSelectedIndex]
    }
    
    // Floating Panels
    private var previewPanel: NSPanel?
    private var switcherPanel: NSPanel?
    private var mouseMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hoverTimer: Timer?
    private var hideTimer: Timer?
    private var lastHoveredPID: pid_t?
    private var lastHoveredDockRect: CGRect = .zero
    private var isMouseInsidePreview: Bool = false
    private var activeModifierForSwitcher: NSEvent.ModifierFlags?
    
    public var statusSubtitle: String? {
        if isEnabled {
            let shortcutLabel = switcherShortcut == .both ? "⌘⇥ & ⌥⇥" : (switcherShortcut == .commandTab ? "⌘⇥" : (switcherShortcut == .optionTab ? "⌥⇥" : "Dock"))
            return "\(shortcutLabel) · \(cardSize.label.components(separatedBy: " ").first ?? "Medium")"
        }
        return nil
    }
    
    private override init() {
        super.init()
        loadSettings()
        if isEnabled {
            startMouseTracking()
            startKeyboardEventTap()
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: keyEnabled)
        
        if let savedDelay = defaults.object(forKey: keyHoverDelay) as? Double,
           let delay = DockDoorHoverDelay(rawValue: savedDelay) {
            self.hoverDelay = delay
        } else {
            self.hoverDelay = .fast
        }
        
        if let savedSize = defaults.string(forKey: keyCardSize),
           let size = DockDoorCardSize(rawValue: savedSize) {
            self.cardSize = size
        } else {
            self.cardSize = .medium
        }
        
        if defaults.object(forKey: keyShowMinimized) != nil {
            self.showMinimized = defaults.bool(forKey: keyShowMinimized)
        } else {
            self.showMinimized = true
        }
        
        if defaults.object(forKey: keyShowActionButtons) != nil {
            self.showActionButtons = defaults.bool(forKey: keyShowActionButtons)
        } else {
            self.showActionButtons = true
        }
        
        if defaults.object(forKey: keySoundFeedback) != nil {
            self.soundFeedback = defaults.bool(forKey: keySoundFeedback)
        } else {
            self.soundFeedback = true
        }
        
        if let savedShortcut = defaults.string(forKey: keySwitcherShortcut),
           let shortcut = DockDoorSwitcherShortcut(rawValue: savedShortcut) {
            self.switcherShortcut = shortcut
        } else {
            self.switcherShortcut = .both
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
            startMouseTracking()
            startKeyboardEventTap()
            playChime(name: "Blow")
        } else {
            stopMouseTracking()
            stopKeyboardEventTap()
            hidePreview(immediate: true)
            cancelSwitcher()
        }
        
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: enabled)
    }
    
    public func setHoverDelay(_ delay: DockDoorHoverDelay) {
        self.hoverDelay = delay
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: isEnabled)
    }
    
    public func setCardSize(_ size: DockDoorCardSize) {
        self.cardSize = size
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: isEnabled)
    }
    
    public func setShowMinimized(_ show: Bool) {
        self.showMinimized = show
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: isEnabled)
    }
    
    public func setShowActionButtons(_ show: Bool) {
        self.showActionButtons = show
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: isEnabled)
    }
    
    public func setSoundFeedback(_ sound: Bool) {
        self.soundFeedback = sound
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: isEnabled)
    }
    
    public func setSwitcherShortcut(_ shortcut: DockDoorSwitcherShortcut) {
        self.switcherShortcut = shortcut
        NotificationCenter.default.post(name: .dockDoorStateDidChange, object: isEnabled)
    }
    
    @discardableResult
    public func checkAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Mouse Tracking & Dock Element Inspection
    
    private func startMouseTracking() {
        stopMouseTracking()
        
        // Global monitor for mouse movement
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleGlobalMouseMove()
        }
    }
    
    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        hoverTimer?.invalidate()
        hoverTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
    }
    
    public func handleGlobalMouseMove() {
        guard isEnabled, !isSwitcherActive else { return }
        let mouseLocation = NSEvent.mouseLocation
        
        // 1. If mouse is hovering over the currently visible preview window, keep it open!
        if let panel = previewPanel, panel.isVisible {
            let panelFrame = panel.frame
            let expandedFrame = panelFrame.insetBy(dx: -15, dy: -15)
            if expandedFrame.contains(mouseLocation) {
                hideTimer?.invalidate()
                hideTimer = nil
                isMouseInsidePreview = true
                return
            }
        }
        isMouseInsidePreview = false
        
        // 2. Detect if mouse is in the Dock region of any screen
        guard let dockInfo = findHoveredDockItem(at: mouseLocation) else {
            // Mouse moved away from the Dock
            scheduleHidePreview()
            return
        }
        
        // Hide debounce cancelled because we are over a dock item
        hideTimer?.invalidate()
        hideTimer = nil
        
        // If hovering over the same application, keep current preview
        if let lastPID = lastHoveredPID, lastPID == dockInfo.pid, previewPanel?.isVisible == true {
            return
        }
        
        // Start hover timer with configured delay
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay.rawValue, repeats: false) { [weak self] _ in
            self?.showPreviewForApp(dockInfo: dockInfo)
        }
    }
    
    struct DockItemInfo {
        let pid: pid_t
        let appName: String
        let appIcon: NSImage?
        let dockRect: CGRect
    }
    
    private func findHoveredDockItem(at mousePoint: NSPoint) -> DockItemInfo? {
        guard let mainScreen = NSScreen.main else { return nil }
        let screenHeight = mainScreen.frame.height
        
        // Query system Accessibility element under cursor
        let sysElement = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        
        // Note: Quartz display point has Y starting from top (0,0 is top-left)
        let quartzPoint = CGPoint(x: mousePoint.x, y: screenHeight - mousePoint.y)
        let res = AXUIElementCopyElementAtPosition(sysElement, Float(quartzPoint.x), Float(quartzPoint.y), &elementRef)
        
        guard res == .success, let element = elementRef else {
            return nil
        }
        
        // Check if element belongs to the Dock process
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid > 0 else { return nil }
        
        let runningApp = NSRunningApplication(processIdentifier: pid)
        guard runningApp?.bundleIdentifier == "com.apple.dock" else {
            return nil
        }
        
        // Check element title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""
        
        // Get Dock element screen position & size
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var itemRect = CGRect.zero
        
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let pVal = posValue, let sVal = sizeValue {
            var point = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(pVal as! AXValue, .cgPoint, &point)
            AXValueGetValue(sVal as! AXValue, .cgSize, &size)
            // Convert to Cocoa bottom-left coordinate
            itemRect = CGRect(x: point.x, y: screenHeight - point.y - size.height, width: size.width, height: size.height)
        } else {
            itemRect = CGRect(x: mousePoint.x - 24, y: mousePoint.y - 24, width: 48, height: 48)
        }
        
        guard !title.isEmpty else { return nil }
        
        // Match title with running user applications
        let apps = NSWorkspace.shared.runningApplications
        if let matched = apps.first(where: { ($0.localizedName?.localizedCaseInsensitiveCompare(title) == .orderedSame || $0.bundleIdentifier?.lowercased().contains(title.lowercased()) == true) && $0.activationPolicy == .regular }) {
            return DockItemInfo(
                pid: matched.processIdentifier,
                appName: matched.localizedName ?? title,
                appIcon: matched.icon,
                dockRect: itemRect
            )
        }
        
        return nil
    }
    
    // MARK: - Capture Window Thumbnails & Present Preview Popover
    
    func showPreviewForApp(dockInfo: DockItemInfo) {
        self.lastHoveredPID = dockInfo.pid
        self.lastHoveredDockRect = dockInfo.dockRect
        self.currentHoveredApp = dockInfo.appName
        self.currentHoveredIcon = dockInfo.appIcon
        
        // Fetch all open & active windows for this app
        let windows = fetchWindows(for: dockInfo.pid, appName: dockInfo.appName, appIcon: dockInfo.appIcon)
        guard !windows.isEmpty else {
            hidePreview(immediate: true)
            return
        }
        
        self.currentWindows = windows
        
        if soundFeedback && AppSettings.shared.playSound {
            NSSound(named: "Tink")?.play()
        }
        
        displayPreviewPanel(dockRect: dockInfo.dockRect, windowCount: windows.count)
    }
    
    private func fetchWindows(for targetPID: pid_t, appName: String, appIcon: NSImage?) -> [DockDoorWindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        var results: [DockDoorWindowInfo] = []
        
        for w in windowList {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid == targetPID else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard bounds.width > 60 && bounds.height > 60 else { continue }
            
            let windowID = CGWindowID(w[kCGWindowNumber as String] as? Int ?? 0)
            let title = w[kCGWindowName as String] as? String ?? ""
            let isMinimized = (w[kCGWindowIsOnscreen as String] as? Bool) == false
            
            // Capture high-DPI image thumbnail
            var thumbnail: NSImage? = nil
            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            
            let item = DockDoorWindowInfo(
                id: windowID,
                title: title.isEmpty ? appName : title,
                pid: targetPID,
                appName: appName,
                appIcon: appIcon,
                bounds: bounds,
                isMinimized: isMinimized,
                thumbnail: thumbnail
            )
            results.append(item)
        }
        
        return results
    }
    
    public func fetchAllOpenWindows() -> [DockDoorWindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        var appMap: [pid_t: NSRunningApplication] = [:]
        for app in runningApps where app.activationPolicy == .regular {
            appMap[app.processIdentifier] = app
        }
        
        var results: [DockDoorWindowInfo] = []
        
        for w in windowList {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, let app = appMap[pid] else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard bounds.width > 80 && bounds.height > 80 else { continue }
            
            let windowID = CGWindowID(w[kCGWindowNumber as String] as? Int ?? 0)
            let title = w[kCGWindowName as String] as? String ?? ""
            let appName = app.localizedName ?? "Application"
            let appIcon = app.icon
            let isMinimized = (w[kCGWindowIsOnscreen as String] as? Bool) == false
            
            if !showMinimized && isMinimized {
                continue
            }
            
            var thumbnail: NSImage? = nil
            if let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            
            let item = DockDoorWindowInfo(
                id: windowID,
                title: title.isEmpty ? appName : title,
                pid: pid,
                appName: appName,
                appIcon: appIcon,
                bounds: bounds,
                isMinimized: isMinimized,
                thumbnail: thumbnail
            )
            results.append(item)
        }
        
        return results
    }
    
    private func displayPreviewPanel(dockRect: CGRect, windowCount: Int) {
        let cardW = cardSize.width
        let cardH = cardSize.height
        
        // Calculate panel sizing: horizontal row of cards
        let count = max(1, min(windowCount, 6))
        let spacing: CGFloat = 12
        let padding: CGFloat = 16
        let totalWidth = (CGFloat(count) * cardW) + (CGFloat(count - 1) * spacing) + (padding * 2)
        let totalHeight = cardH + 54 + (padding * 2)
        
        if previewPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
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
            
            let hosting = NSHostingView(rootView: DockDoorPreviewRootView())
            panel.contentView = hosting
            self.previewPanel = panel
        } else {
            previewPanel?.setContentSize(NSSize(width: totalWidth, height: totalHeight))
        }
        
        guard let panel = previewPanel, let screen = NSScreen.main else { return }
        
        // Center panel horizontally over dock icon, right above the dock
        var panelX = dockRect.midX - (totalWidth / 2)
        panelX = max(screen.visibleFrame.minX + 10, min(screen.visibleFrame.maxX - totalWidth - 10, panelX))
        
        let panelY = dockRect.maxY + 14
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        
        panel.alphaValue = 0.0
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1.0
        }
    }
    
    private func scheduleHidePreview() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        
        guard previewPanel?.isVisible == true else { return }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            self?.hidePreview(immediate: false)
        }
    }
    
    public func hidePreview(immediate: Bool = false) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
        lastHoveredPID = nil
        
        guard let panel = previewPanel, panel.isVisible else { return }
        
        if immediate {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                if panel.alphaValue == 0.0 {
                    panel.orderOut(nil)
                }
            })
        }
    }
    
    // MARK: - Command+Tab / Alt+Tab Switcher HUD Logic
    
    public func triggerSwitcherHUD(modifier: NSEvent.ModifierFlags) {
        let windows = fetchAllOpenWindows()
        guard !windows.isEmpty else { return }
        
        self.activeModifierForSwitcher = modifier
        self.switcherWindows = windows
        // By default, select the 2nd window (index 1) just like macOS Cmd+Tab, or 0 if only 1 window
        self.switcherSelectedIndex = windows.count > 1 ? 1 : 0
        self.isSwitcherActive = true
        
        if soundFeedback && AppSettings.shared.playSound {
            NSSound(named: "Pop")?.play()
        }
        
        showSwitcherPanel()
    }
    
    private func showSwitcherPanel() {
        hidePreview(immediate: true)
        
        if switcherPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hosting = NSHostingView(rootView: DockDoorSwitcherHUDView())
            panel.contentView = hosting
            self.switcherPanel = panel
        }
        
        guard let panel = switcherPanel, let screen = NSScreen.main else { return }
        
        // Center on the active screen
        let screenFrame = screen.frame
        let panelW: CGFloat = min(screenFrame.width * 0.85, CGFloat(max(1, switcherWindows.count)) * 288 + 60)
        let panelH: CGFloat = 330
        
        panel.setContentSize(NSSize(width: panelW, height: panelH))
        let originX = screenFrame.midX - (panelW / 2)
        let originY = screenFrame.midY - (panelH / 2)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }
    
    public func selectNextWindow() {
        guard !switcherWindows.isEmpty else { return }
        switcherSelectedIndex = (switcherSelectedIndex + 1) % switcherWindows.count
        if soundFeedback && AppSettings.shared.playSound {
            NSSound(named: "Tink")?.play()
        }
    }
    
    public func selectPreviousWindow() {
        guard !switcherWindows.isEmpty else { return }
        switcherSelectedIndex = (switcherSelectedIndex - 1 + switcherWindows.count) % switcherWindows.count
        if soundFeedback && AppSettings.shared.playSound {
            NSSound(named: "Tink")?.play()
        }
    }
    
    public func selectWindow(at index: Int) {
        guard index >= 0 && index < switcherWindows.count else { return }
        switcherSelectedIndex = index
    }
    
    public func commitSwitcherSelection() {
        guard isSwitcherActive else { return }
        isSwitcherActive = false
        activeModifierForSwitcher = nil
        
        if let selected = selectedSwitcherWindow {
            focusWindow(selected)
        }
        
        hideSwitcherPanel()
    }
    
    public func cancelSwitcher() {
        isSwitcherActive = false
        activeModifierForSwitcher = nil
        hideSwitcherPanel()
    }
    
    public func closeSelectedWindow() {
        guard let selected = selectedSwitcherWindow else { return }
        closeWindow(selected)
        
        // Remove from list
        switcherWindows.removeAll(where: { $0.id == selected.id })
        if switcherWindows.isEmpty {
            cancelSwitcher()
        } else {
            switcherSelectedIndex = min(switcherSelectedIndex, switcherWindows.count - 1)
        }
    }
    
    public func minimizeSelectedWindow() {
        guard let selected = selectedSwitcherWindow else { return }
        minimizeWindow(selected)
    }
    
    public func quitSelectedApp() {
        guard let selected = selectedSwitcherWindow else { return }
        if let app = NSRunningApplication(processIdentifier: selected.pid) {
            app.terminate()
        }
        switcherWindows.removeAll(where: { $0.pid == selected.pid })
        if switcherWindows.isEmpty {
            cancelSwitcher()
        } else {
            switcherSelectedIndex = min(switcherSelectedIndex, switcherWindows.count - 1)
        }
    }
    
    public func hideSelectedApp() {
        guard let selected = selectedSwitcherWindow else { return }
        if let app = NSRunningApplication(processIdentifier: selected.pid) {
            app.hide()
        }
        switcherWindows.removeAll(where: { $0.pid == selected.pid })
        if switcherWindows.isEmpty {
            cancelSwitcher()
        } else {
            switcherSelectedIndex = min(switcherSelectedIndex, switcherWindows.count - 1)
        }
    }
    
    private func hideSwitcherPanel() {
        guard let panel = switcherPanel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
    
    // MARK: - Global Keyboard Event Tap
    
    private func startKeyboardEventTap() {
        stopKeyboardEventTap()
        
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)
        
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
                let service = Unmanaged<DockDoorService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEventTap(proxy: proxy, type: type, event: event)
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
    
    private func stopKeyboardEventTap() {
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
    
    private func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // 1. Handle Key Down
        if type == .keyDown {
            let isTab = (keyCode == 48)
            let isCmd = flags.contains(.maskCommand)
            let isAlt = flags.contains(.maskAlternate)
            let isShift = flags.contains(.maskShift)
            
            // Check if switcher is already open
            if isSwitcherActive {
                if isTab {
                    DispatchQueue.main.async {
                        if isShift {
                            self.selectPreviousWindow()
                        } else {
                            self.selectNextWindow()
                        }
                    }
                    return nil // Intercept Tab key
                }
                
                // Navigation Arrow Keys
                if keyCode == 124 || keyCode == 125 { // Right / Down
                    DispatchQueue.main.async { self.selectNextWindow() }
                    return nil
                }
                if keyCode == 123 || keyCode == 126 { // Left / Up
                    DispatchQueue.main.async { self.selectPreviousWindow() }
                    return nil
                }
                
                // Return (36) or Space (49) -> Commit Selection
                if keyCode == 36 || keyCode == 49 {
                    DispatchQueue.main.async { self.commitSwitcherSelection() }
                    return nil
                }
                
                // Escape (53) -> Cancel
                if keyCode == 53 {
                    DispatchQueue.main.async { self.cancelSwitcher() }
                    return nil
                }
                
                // W (13) or Delete (51) -> Close Window
                if keyCode == 13 || keyCode == 51 {
                    DispatchQueue.main.async { self.closeSelectedWindow() }
                    return nil
                }
                
                // M (46) -> Minimize Window
                if keyCode == 46 {
                    DispatchQueue.main.async { self.minimizeSelectedWindow() }
                    return nil
                }
                
                // Q (12) -> Quit App
                if keyCode == 12 {
                    DispatchQueue.main.async { self.quitSelectedApp() }
                    return nil
                }
                
                // H (4) -> Hide App
                if keyCode == 4 {
                    DispatchQueue.main.async { self.hideSelectedApp() }
                    return nil
                }
            } else {
                // Switcher not active -> Check trigger shortcuts
                if isTab {
                    let cmdAllowed = (switcherShortcut == .commandTab || switcherShortcut == .both)
                    let altAllowed = (switcherShortcut == .optionTab || switcherShortcut == .both)
                    
                    if isCmd && cmdAllowed {
                        DispatchQueue.main.async {
                            self.triggerSwitcherHUD(modifier: .command)
                        }
                        return nil // Intercept Cmd+Tab to show DockDoor switcher
                    } else if isAlt && altAllowed {
                        DispatchQueue.main.async {
                            self.triggerSwitcherHUD(modifier: .option)
                        }
                        return nil // Intercept Option+Tab to show DockDoor switcher
                    }
                }
            }
        }
        
        // 2. Handle Modifier Flags Changed (Detect key release to switch)
        if type == .flagsChanged && isSwitcherActive {
            if let mod = activeModifierForSwitcher {
                if mod == .command && !flags.contains(.maskCommand) {
                    DispatchQueue.main.async {
                        self.commitSwitcherSelection()
                    }
                } else if mod == .option && !flags.contains(.maskAlternate) {
                    DispatchQueue.main.async {
                        self.commitSwitcherSelection()
                    }
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - Window Management Actions
    
    public func focusWindow(_ window: DockDoorWindowInfo) {
        hidePreview(immediate: true)
        
        // 1. Activate application
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        // 2. Unminimize and bring window to front via AXUIElement
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let winArray = windowsRef as? [AXUIElement] {
            for axWin in winArray {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let t = titleRef as? String ?? ""
                
                if t == window.title || winArray.count == 1 {
                    // Unminimize if needed
                    AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    // Raise to front
                    AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                    break
                }
            }
        }
    }
    
    public func closeWindow(_ window: DockDoorWindowInfo) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let winArray = windowsRef as? [AXUIElement] {
            for axWin in winArray {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let t = titleRef as? String ?? ""
                
                if t == window.title || winArray.count == 1 {
                    var closeButtonRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
                       let closeBtn = closeButtonRef {
                        AXUIElementPerformAction(closeBtn as! AXUIElement, kAXPressAction as CFString)
                    }
                    break
                }
            }
        }
        
        currentWindows.removeAll(where: { $0.id == window.id })
        if currentWindows.isEmpty {
            hidePreview(immediate: true)
        }
    }
    
    public func minimizeWindow(_ window: DockDoorWindowInfo) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let winArray = windowsRef as? [AXUIElement] {
            for axWin in winArray {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let t = titleRef as? String ?? ""
                
                if t == window.title || winArray.count == 1 {
                    AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                    break
                }
            }
        }
    }
    
    public func zoomWindow(_ window: DockDoorWindowInfo) {
        let appElement = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let winArray = windowsRef as? [AXUIElement] {
            for axWin in winArray {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let t = titleRef as? String ?? ""
                
                if t == window.title || winArray.count == 1 {
                    var zoomButtonRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWin, kAXZoomButtonAttribute as CFString, &zoomButtonRef) == .success,
                       let zoomBtn = zoomButtonRef {
                        AXUIElementPerformAction(zoomBtn as! AXUIElement, kAXPressAction as CFString)
                    }
                    break
                }
            }
        }
    }
    
    public func openNewWindow(for window: DockDoorWindowInfo) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
            
            // Dispatch ⌘N key event to the application
            let src = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 45, keyDown: true) // N key = 45
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 45, keyDown: false)
            keyUp?.flags = .maskCommand
            
            keyDown?.postToPid(window.pid)
            keyUp?.postToPid(window.pid)
        }
    }
    
    private func playChime(name: String) {
        guard soundFeedback && AppSettings.shared.playSound else { return }
        NSSound(named: name)?.play()
    }
}
