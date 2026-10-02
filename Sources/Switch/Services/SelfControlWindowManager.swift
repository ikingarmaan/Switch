import Cocoa
import SwiftUI

public final class SelfControlWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SelfControlWindowManager()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let selfControlView = SelfControlView()
        let hostingController = NSHostingController(rootView: selfControlView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.center()
        newWindow.title = "Self Control & Recovery Tracker"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.titlebarAppearsTransparent = true
        newWindow.minSize = NSSize(width: 650, height: 600)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Keeps reference for clean reopening
    }
}
