import Cocoa
import SwiftUI

public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func showSettings() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.center()
        newWindow.title = "Switch Settings"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.titlebarAppearsTransparent = true
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Keeps reference for clean reopening
    }
}
