import Foundation
import Cocoa
import Combine
import SwiftUI

public extension Notification.Name {
    static let floatingFinderStateDidChange = Notification.Name("SwitchFloatingFinderStateDidChange")
}

public enum FloatingFinderLevel: Int32, CaseIterable, Identifiable, Sendable {
    case floating = 3 // CGWindowLevelForKey(.floatingWindow)
    case topmost = 8  // CGWindowLevelForKey(.modalPanelWindow)
    
    public var id: Int32 { rawValue }
    
    public var label: String {
        switch self {
        case .floating: return "Floating (Above All Apps · Level 3)"
        case .topmost: return "Topmost (Above Panels · Level 8)"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .floating: return "Floating"
        case .topmost: return "Topmost"
        }
    }
    
    public var windowLevel: NSWindow.Level {
        switch self {
        case .floating: return .floating
        case .topmost: return .modalPanel
        }
    }
}

// MARK: - Dedicated Floating Panel Subclass

public final class FloatingFinderPanel: NSPanel, NSWindowDelegate {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    
    public override func performClose(_ sender: Any?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                FloatingFinderService.shared.setEnabled(false)
            }
        }
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                FloatingFinderService.shared.setEnabled(false)
            }
        }
        return false // service handles orderOut
    }
}

// MARK: - Floating Finder Service

public final class FloatingFinderService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = FloatingFinderService()
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var currentLevel: FloatingFinderLevel = .floating
    @Published public private(set) var opacity: Double = 1.0
    
    private let keyEnabled = "switch.floatingFinder.enabled"
    private let keyLevel = "switch.floatingFinder.level"
    private let keyOpacity = "switch.floatingFinder.opacity"
    
    private var floatingPanel: FloatingFinderPanel?
    private var monitorTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // SkyLight Dynamic Linking (Secondary/native fallback)
    private typealias CGSConnectionID = Int32
    private typealias CGSWindowID = UInt32
    private typealias CGSDefaultConnFunc = @convention(c) () -> CGSConnectionID
    private typealias SLSSetWindowLevelFunc = @convention(c) (CGSConnectionID, CGSWindowID, Int32) -> Int32
    private typealias SLSSetWindowAlphaFunc = @convention(c) (CGSConnectionID, CGSWindowID, Float) -> Int32
    
    private let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    }()
    
    private lazy var defaultConnection: CGSConnectionID = {
        guard let handle = skyLightHandle,
              let sym = dlsym(handle, "_CGSDefaultConnection") ?? dlsym(handle, "CGSDefaultConnection") else {
            return 0
        }
        let fn = unsafeBitCast(sym, to: CGSDefaultConnFunc.self)
        return fn()
    }()
    
    private lazy var setWindowLevelFunc: SLSSetWindowLevelFunc? = {
        guard let handle = skyLightHandle,
              let sym = dlsym(handle, "SLSSetWindowLevel") ?? dlsym(handle, "CGSSetWindowLevel") else {
            return nil
        }
        return unsafeBitCast(sym, to: SLSSetWindowLevelFunc.self)
    }()
    
    private lazy var setWindowAlphaFunc: SLSSetWindowAlphaFunc? = {
        guard let handle = skyLightHandle,
              let sym = dlsym(handle, "SLSSetWindowAlpha") ?? dlsym(handle, "CGSSetWindowAlpha") else {
            return nil
        }
        return unsafeBitCast(sym, to: SLSSetWindowAlphaFunc.self)
    }()
    
    private override init() {
        super.init()
        self.isEnabled = UserDefaults.standard.bool(forKey: keyEnabled)
        if let rawLevel = UserDefaults.standard.object(forKey: keyLevel) as? Int32,
           let lvl = FloatingFinderLevel(rawValue: rawLevel) {
            self.currentLevel = lvl
        }
        let savedOpacity = UserDefaults.standard.double(forKey: keyOpacity)
        if savedOpacity >= 0.5 && savedOpacity <= 1.0 {
            self.opacity = savedOpacity
        }
        
        if isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated {
                    FloatingFinderService.shared.showPanel()
                    FloatingFinderService.shared.startMonitoring()
                }
            }
        }
    }
    
    public var statusSubtitle: String {
        guard isEnabled else { return "Standard Layer" }
        if opacity < 1.0 {
            return "\(currentLevel.shortLabel) · \(Int(opacity * 100))% Opacity"
        } else {
            return "\(currentLevel.shortLabel) on Top"
        }
    }
    
    // MARK: - Toggle & Configuration
    
    public func setEnabled(_ enable: Bool) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.applyEnabled(enable)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.applyEnabled(enable)
                }
            }
        }
    }
    
    @MainActor
    private func applyEnabled(_ enable: Bool) {
        guard isEnabled != enable else {
            if enable && floatingPanel?.isVisible != true {
                showPanel()
            }
            return
        }
        
        isEnabled = enable
        UserDefaults.standard.set(enable, forKey: keyEnabled)
        
        if enable {
            showPanel()
            startMonitoring()
            applyFloatingState()
        } else {
            hidePanel()
            stopMonitoring()
            restoreNormalState()
        }
        
        NotificationCenter.default.post(name: .floatingFinderStateDidChange, object: enable)
    }
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setLevel(_ level: FloatingFinderLevel) {
        currentLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: keyLevel)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let panel = self.floatingPanel {
                panel.level = level.windowLevel
            }
            if self.isEnabled {
                self.applyFloatingState()
            }
            NotificationCenter.default.post(name: .floatingFinderStateDidChange, object: self.isEnabled)
        }
    }
    
    public func setOpacity(_ newOpacity: Double) {
        let clamped = min(1.0, max(0.5, newOpacity))
        opacity = clamped
        UserDefaults.standard.set(clamped, forKey: keyOpacity)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let panel = self.floatingPanel {
                panel.alphaValue = CGFloat(clamped)
            }
            if self.isEnabled {
                self.applyFloatingState()
            }
            NotificationCenter.default.post(name: .floatingFinderStateDidChange, object: self.isEnabled)
        }
    }
    
    public func openNewFinderWindow() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                FloatingFinderViewModel.shared.syncWithNativeFinder()
                FloatingFinderService.shared.applyFloatingState()
            }
        }
    }
    
    // MARK: - Floating Panel Presentation
    
    @MainActor
    public func showPanel() {
        if let panel = floatingPanel {
            panel.level = currentLevel.windowLevel
            panel.alphaValue = CGFloat(opacity)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: false)
            return
        }
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let initialWidth: CGFloat = 460
        let initialHeight: CGFloat = 520
        let initialOrigin = NSPoint(
            x: screenRect.maxX - initialWidth - 30,
            y: screenRect.maxY - initialHeight - 40
        )
        
        let panel = FloatingFinderPanel(
            contentRect: NSRect(origin: initialOrigin, size: NSSize(width: initialWidth, height: initialHeight)),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.delegate = panel
        panel.title = "Floating Finder"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = currentLevel.windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 360, height: 48)
        panel.alphaValue = CGFloat(opacity)
        panel.setFrameAutosaveName("SwitchFloatingFinderPanel")
        
        let contentView = FloatingFinderView(vm: FloatingFinderViewModel.shared)
        panel.contentView = NSHostingView(rootView: contentView)
        
        self.floatingPanel = panel
        panel.makeKeyAndOrderFront(nil)
        
        // Auto-sync directory with native Finder on first appearance
        FloatingFinderViewModel.shared.syncWithNativeFinder()
    }
    
    @MainActor
    public func hidePanel() {
        floatingPanel?.orderOut(nil)
    }
    
    // MARK: - Native Finder Window Management & SkyLight Support
    
    public func applyFloatingState() {
        guard isEnabled else { return }
        let cid = defaultConnection
        guard cid != 0, let setLevel = setWindowLevelFunc else { return }
        let alphaFunc = setWindowAlphaFunc
        
        let targetWindows = getFinderWindowIDs()
        let targetLevel = currentLevel.rawValue
        let targetAlpha = Float(opacity)
        
        for wid in targetWindows {
            _ = setLevel(cid, wid, targetLevel)
            if let alphaFn = alphaFunc {
                _ = alphaFn(cid, wid, targetAlpha)
            }
        }
    }
    
    public func restoreNormalState() {
        let cid = defaultConnection
        guard cid != 0, let setLevel = setWindowLevelFunc else { return }
        let alphaFunc = setWindowAlphaFunc
        
        let targetWindows = getFinderWindowIDs(includeAnyLayer: true)
        
        for wid in targetWindows {
            _ = setLevel(cid, wid, 0)
            if let alphaFn = alphaFunc {
                _ = alphaFn(cid, wid, 1.0)
            }
        }
    }
    
    private func getFinderWindowIDs(includeAnyLayer: Bool = false) -> [CGSWindowID] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        var result: [CGSWindowID] = []
        
        for w in windowList {
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "Finder" else {
                continue
            }
            guard let widInt = w[kCGWindowNumber as String] as? Int, widInt > 0 else {
                continue
            }
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            
            // Exclude desktop background layer
            guard layer > -1000 else {
                continue
            }
            
            if let bounds = w[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                guard width >= 150 && height >= 100 else {
                    continue
                }
            }
            
            if includeAnyLayer || layer == 0 || layer == 3 || layer == 8 {
                result.append(CGSWindowID(widInt))
            }
        }
        
        return result
    }
    
    // MARK: - Monitoring Lifecycle
    
    public func startMonitoring() {
        stopMonitoring()
        
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.applyFloatingState()
        }
        
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier == "com.apple.finder" {
                    self?.applyFloatingState()
                }
            }
            .store(in: &cancellables)
    }
    
    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        cancellables.removeAll()
    }
}

