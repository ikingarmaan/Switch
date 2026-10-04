import Cocoa
import SwiftUI

public final class MacCleanerWindowManager: NSObject, NSWindowDelegate {
    public static let shared = MacCleanerWindowManager()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            CleanCacheService.shared.scanInstalledApps()
            CleanCacheService.shared.refreshDiagnostics()
            return
        }
        
        let cleanerView = MacCleanerView()
        let hostingController = NSHostingController(rootView: cleanerView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.center()
        newWindow.title = "Mac Cleaner & App Uninstaller"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.titlebarAppearsTransparent = true
        newWindow.minSize = NSSize(width: 760, height: 520)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        CleanCacheService.shared.scanInstalledApps()
        CleanCacheService.shared.refreshDiagnostics()
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Retain reference for fast reopening
    }
}
