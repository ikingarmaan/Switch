import Cocoa
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover = NSPopover()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Set application icon from bundled resources
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = image
        }
        
        // Prevent macOS from automatically terminating the app
        PersistenceService.shared.enablePersistence()
        
        // Run as menu bar accessory app without Dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Register native macOS Finder contextual services provider
        NSApp.servicesProvider = FinderServicesProvider.shared
        NSUpdateDynamicServices()
        
        setupMainMenu()
        setupStatusItem()
        setupNotificationObservers()
        
        // Pre-warm all singletons before SwiftUI popover hierarchy is loaded
        _ = KeepAwakeService.shared
        _ = NightShiftService.shared
        _ = KeyboardLockService.shared
        _ = CameraPreviewService.shared
        _ = CountdownTimerService.shared
        _ = AmphetamineService.shared
        _ = MouseJigglerService.shared
        _ = AutoScrollService.shared
        _ = GooglyEyesService.shared
        _ = VolumeBoostService.shared
        _ = SystemMonitorService.shared
        SystemMonitorService.shared.restoreStateIfNeeded()
        _ = LoomRecorderService.shared
        _ = VPNService.shared
        _ = FolderTidyService.shared
        _ = DNSService.shared
        _ = KnockScreenshotService.shared
        _ = ClipboardService.shared
        _ = StickyNotesService.shared
        _ = SelfControlService.shared
        _ = RAMGPUResetService.shared
        _ = WallpaperChangerService.shared
        _ = WisprFlowService.shared
        _ = DockDoorService.shared
        _ = MouseBoostProService.shared
        
        setupPopover()
        
        // Automatically pop open the Switch panel on launch so user immediately sees the app!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            self.showPopover(button)
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let button = statusItem?.button {
            showPopover(button)
        }
        return true
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Switch", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Switch", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Edit Menu: Provides standard system clipboard and text actions (⌘C, ⌘V, ⌘X, ⌘A, ⌘Z)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let host = (url.host ?? url.path).lowercased()
            if host.contains("clipboard") {
                ClipboardService.shared.toggleWindow()
            } else if host.contains("control") || host.contains("selfcontrol") || host.contains("clarity") || host.contains("recovery") {
                SelfControlWindowManager.shared.showWindow()
            } else {
                if let button = statusItem?.button {
                    showPopover(button)
                }
            }
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarIconChanged(_:)),
            name: .menuBarIconDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timerTickReceived(_:)),
            name: .timerTick,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(amphetamineTickReceived(_:)),
            name: .amphetamineTick,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.togglePopover"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let appDelegate = NSApp.delegate as? AppDelegate,
                   let button = appDelegate.statusItem?.button {
                    appDelegate.togglePopover(button)
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.toggleClipboard"),
            object: nil,
            queue: .main
        ) { _ in
            ClipboardService.shared.toggleWindow()
        }
    }
    
    @objc private func timerTickReceived(_ notification: Notification) {
        guard let button = statusItem?.button else { return }
        if let timeStr = notification.object as? String, !timeStr.isEmpty {
            button.title = " \(timeStr)"
        } else if AmphetamineService.shared.isActive {
            let a = AmphetamineService.shared
            button.title = a.isIndefinite ? " ☕" : " ☕ \(a.formattedRemainingTime)"
        } else {
            button.title = ""
        }
    }
    
    @objc private func amphetamineTickReceived(_ notification: Notification) {
        if CountdownTimerService.shared.isRunning { return }
        guard let button = statusItem?.button else { return }
        if let timeStr = notification.object as? String, !timeStr.isEmpty {
            button.title = AmphetamineService.shared.isIndefinite ? " ☕" : " ☕ \(timeStr)"
        } else {
            button.title = ""
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon(name: AppSettings.shared.menuBarIcon)
        
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Switch - macOS Toggles"
        }
    }
    
    private func updateStatusItemIcon(name: String) {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Switch")?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "⑂"
        }
    }
    
    @objc private func menuBarIconChanged(_ notification: Notification) {
        if let iconName = notification.object as? String {
            updateStatusItemIcon(name: iconName)
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        AmphetamineService.shared.stop()
        MouseJigglerService.shared.stop()
        SystemMonitorService.shared.stop()
        LoomRecorderService.shared.stopSession()
    }
    
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 345, height: 760)
        popover.contentViewController = NSHostingController(rootView: SwitchListView())
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            // Right click context menu
            let menu = NSMenu()
            let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)
            menu.addItem(NSMenuItem.separator())
            let aboutItem = NSMenuItem(title: "About Switch", action: #selector(showAbout), keyEquivalent: "")
            aboutItem.target = self
            menu.addItem(aboutItem)
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit Switch", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            togglePopover(sender)
        }
    }
    
    @objc private func openSettings() {
        if popover.isShown {
            popover.performClose(nil)
        }
        SettingsWindowManager.shared.showSettings()
    }
    
    public func showPopover(_ sender: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    public func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Switch for macOS"
        alert.informativeText = "A sleek, native menu bar utility for toggling system settings instantly."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quitApp() {
        PersistenceService.shared.disablePersistence()
        NSApplication.shared.terminate(nil)
    }
}
