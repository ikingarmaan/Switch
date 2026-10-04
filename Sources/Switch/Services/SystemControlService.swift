import Foundation
import AppKit

public enum SwitchType: String, CaseIterable, Identifiable, Sendable {
    case hideDesktop = "hideDesktop"
    case keepAwake = "keepAwake"
    case screenSaver = "screenSaver"
    case nightShift = "nightShift"
    case autohideDock = "autohideDock"
    case autohideMenuBar = "autohideMenuBar"
    case hiddenFiles = "hiddenFiles"
    case lockKeyboard = "lockKeyboard"
    case cameraPreview = "cameraPreview"
    case timer = "timer"
    case amphetamine = "amphetamine"
    case mouseJiggler = "mouseJiggler"
    case googlyEyes = "googlyEyes"
    case volumeBoost = "volumeBoost"
    case systemMonitor = "systemMonitor"
    case loomRecorder = "loomRecorder"
    
    // Additional tools
    case lockScreen = "lockScreen"
    case emptyTrash = "emptyTrash"
    case forceQuitApps = "forceQuitApps"
    case autoVPN = "autoVPN"
    case tidyFolders = "tidyFolders"
    case adblockDNS = "adblockDNS"
    case knockScreenshot = "knockScreenshot"
    case clipboardManager = "clipboardManager"
    case autoScroll = "autoScroll"
    case stickyNotes = "stickyNotes"
    case selfControl = "selfControl"
    case locationServices = "locationServices"
    case ramGpuReset = "ramGpuReset"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .hideDesktop: return "Hide Desktop Icons"
        case .keepAwake: return "Keep Awake"
        case .screenSaver: return "Screen Saver"
        case .nightShift: return "Night Shift"
        case .autohideDock: return "AutoHide Dock"
        case .autohideMenuBar: return "AutoHide Menu Bar"
        case .hiddenFiles: return "Show Hidden Files"
        case .lockKeyboard: return "Lock Keyboard"
        case .cameraPreview: return "Camera Preview"
        case .timer: return "Countdown Timer"
        case .amphetamine: return "Amphetamine (Lid Awake)"
        case .mouseJiggler: return "Auto Mouse Mover"
        case .googlyEyes: return "Googly Eyes"
        case .volumeBoost: return "Volume Boost"
        case .systemMonitor: return "System Monitor"
        case .loomRecorder: return "Loom Screen Recorder"
        case .lockScreen: return "Lock Screen"
        case .emptyTrash: return "Empty Trash"
        case .forceQuitApps: return "Force Quit All Apps"
        case .autoVPN: return "Auto VPN"
        case .tidyFolders: return "Tidy Up Folders"
        case .adblockDNS: return "AdBlock DNS"
        case .knockScreenshot: return "Knock Screenshot"
        case .clipboardManager: return "Clipboard History"
        case .autoScroll: return "Auto Scroll"
        case .stickyNotes: return "Sticky Notes"
        case .selfControl: return "Self Control & Recovery"
        case .locationServices: return "Location Services"
        case .ramGpuReset: return "RAM & GPU Reset"
        }
    }
    
    public var iconName: String {
        switch self {
        case .hideDesktop: return "display"
        case .keepAwake: return "eye.slash"
        case .screenSaver: return "tv"
        case .nightShift: return "moon.stars.fill"
        case .autohideDock: return "dock.rectangle"
        case .autohideMenuBar: return "menubar.rectangle"
        case .hiddenFiles: return "eye.slash"
        case .lockKeyboard: return "keyboard"
        case .cameraPreview: return "camera.fill"
        case .timer: return "timer"
        case .amphetamine: return "pill.fill"
        case .mouseJiggler: return "cursorarrow.motionlines"
        case .googlyEyes: return "eyes"
        case .volumeBoost: return "speaker.wave.3.fill"
        case .systemMonitor: return "gauge.with.needle.fill"
        case .loomRecorder: return "record.circle.fill"
        case .lockScreen: return "lock.fill"
        case .emptyTrash: return "trash.fill"
        case .forceQuitApps: return "xmark.app.fill"
        case .autoVPN: return "shield.lefthalf.filled"
        case .tidyFolders: return "sparkles.rectangle.stack"
        case .adblockDNS: return "shield.fill"
        case .knockScreenshot: return "hand.tap.fill"
        case .clipboardManager: return "doc.on.clipboard.fill"
        case .autoScroll: return "arrow.up.and.down.circle.fill"
        case .stickyNotes: return "note.text"
        case .selfControl: return "shield.checkered"
        case .locationServices: return "location.fill"
        case .ramGpuReset: return "bolt.shield.fill"
        }
    }
    
    public var isActionOnly: Bool {
        switch self {
        case .lockScreen, .emptyTrash:
            return true
        default:
            return false
        }
    }
}

public enum MenuBarAutoHideMode: String, CaseIterable, Identifiable, Sendable {
    case fullScreenOnly = "fullScreenOnly"
    case always = "always"
    case desktopOnly = "desktopOnly"
    case never = "never"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .fullScreenOnly: return "In Full Screen Only"
        case .always: return "Always"
        case .desktopOnly: return "On Desktop Only"
        case .never: return "Never"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .fullScreenOnly: return "Full Screen"
        case .always: return "Always"
        case .desktopOnly: return "Desktop"
        case .never: return "Never"
        }
    }
    
    public var hideOnDesktop: Bool {
        switch self {
        case .always, .desktopOnly: return true
        case .fullScreenOnly, .never: return false
        }
    }
    
    public var visibleInFullscreen: Bool {
        switch self {
        case .fullScreenOnly, .always: return false
        case .never, .desktopOnly: return true
        }
    }
    
    public var controlCenterOption: Int {
        switch self {
        case .never: return 0
        case .always: return 1
        case .desktopOnly: return 2
        case .fullScreenOnly: return 3
        }
    }
}

public extension Notification.Name {
    static let menuBarAutoHideModeDidChange = Notification.Name("menuBarAutoHideModeDidChange")
}

public final class SystemControlService: @unchecked Sendable {
    public static let shared = SystemControlService()
    
    public var currentMenuBarAutoHideMode: MenuBarAutoHideMode {
        getMenuBarAutoHideMode()
    }
    
    private init() {}
    
    // MARK: - Query Status
    
    public func getStatus(for type: SwitchType) -> (isOn: Bool, subtitle: String?) {
        switch type {
        case .hideDesktop:
            let val = Shell.run("defaults read com.apple.finder CreateDesktop 2>/dev/null")
            let isHidden = (val == "0" || val.lowercased() == "false")
            return (isHidden, nil)
            
        case .keepAwake:
            return (KeepAwakeService.shared.isEnabled(), nil)
            
        case .screenSaver:
            let idleTimeStr = Shell.run("defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null")
            let idleSeconds = Int(idleTimeStr) ?? 0
            if idleSeconds > 0 {
                let minutes = max(1, idleSeconds / 60)
                return (true, "\(minutes) min")
            } else {
                return (false, "5 min")
            }
            
        case .nightShift:
            let ns = NightShiftService.shared
            return (ns.isEnabled(), ns.subtitle)
            
        case .autohideDock:
            let val = Shell.run("defaults read com.apple.dock autohide 2>/dev/null")
            return (val == "1" || val.lowercased() == "true", nil)
            
        case .autohideMenuBar:
            let mode = getMenuBarAutoHideMode()
            return (mode.hideOnDesktop, mode.shortLabel)
            
        case .hiddenFiles:
            let val = Shell.run("defaults read com.apple.Finder AppleShowAllFiles 2>/dev/null")
            return (val == "1" || val.lowercased() == "true", nil)
            
        case .lockKeyboard:
            return (KeyboardLockService.shared.isLocked, nil)
            
        case .cameraPreview:
            return (CameraPreviewService.shared.isRunning, nil)
            
        case .timer:
            let s = CountdownTimerService.shared
            let sub = s.isRunning ? s.formattedRemainingTime : s.formattedSelectedDuration
            return (s.isRunning, sub)
            
        case .amphetamine:
            let a = AmphetamineService.shared
            let sub = a.isActive ? a.formattedRemainingTime : a.formattedSelectedDuration
            return (a.isActive, sub)
            
        case .mouseJiggler:
            let m = MouseJigglerService.shared
            return (m.isActive, m.formattedSubtitle)
            
        case .googlyEyes:
            let g = GooglyEyesService.shared
            return (g.isEnabled, g.isEnabled ? g.currentEmotion.label : nil)
            
        case .volumeBoost:
            let v = VolumeBoostService.shared
            return (v.isActive, v.isActive ? v.selectedLevel.label : nil)
            
        case .systemMonitor:
            let mon = SystemMonitorService.shared
            return (mon.isEnabled, mon.isEnabled ? "Menu Bar" : nil)
            
        case .loomRecorder:
            let loom = LoomRecorderService.shared
            if loom.isRecording {
                return (true, loom.formattedDuration)
            } else if loom.isSessionActive {
                return (true, "Ready")
            } else {
                return (false, nil)
            }
            
        case .lockScreen, .emptyTrash:
            return (false, nil)
            
        case .forceQuitApps:
            let count = getRunningUserApps().count
            return (false, count > 0 ? "\(count) apps open" : "No open apps")
            
        case .autoVPN:
            let vpn = VPNService.shared
            return (vpn.isConnected, vpn.statusSubtitle)
            
        case .tidyFolders:
            let tidy = FolderTidyService.shared
            return (tidy.isOrganizing, tidy.statusSubtitle)
            
        case .adblockDNS:
            let dns = DNSService.shared
            return (dns.isEnabled, dns.statusSubtitle)
            
        case .knockScreenshot:
            let knock = KnockScreenshotService.shared
            return (knock.isListening, knock.statusSubtitle)
            
        case .clipboardManager:
            let clip = ClipboardService.shared
            return (clip.isEnabled, clip.statusSubtitle)
            
        case .autoScroll:
            let scroll = AutoScrollService.shared
            return (scroll.isActive, scroll.statusSubtitle)
            
        case .stickyNotes:
            let notes = StickyNotesService.shared
            return (notes.isVisible, notes.statusSubtitle)
            
        case .selfControl:
            let sc = SelfControlService.shared
            return (sc.isShieldActive, sc.statusSubtitle)
            
        case .locationServices:
            let loc = LocationService.shared
            _ = loc.checkStatus()
            return (loc.isEnabled, loc.statusSubtitle)
            
        case .ramGpuReset:
            let ram = RAMGPUResetService.shared
            return (ram.isAutoGuardEnabled, ram.statusSubtitle)
        }
    }
    
    // MARK: - Toggle Actions
    
    public func setStatus(for type: SwitchType, isOn: Bool) {
        switch type {
        case .hideDesktop:
            // When ON, icons are hidden (CreateDesktop = false)
            let val = isOn ? "false" : "true"
            _ = Shell.run("defaults write com.apple.finder CreateDesktop -bool \(val); killall Finder")
            
        case .keepAwake:
            KeepAwakeService.shared.setEnabled(isOn)
            
        case .screenSaver:
            if isOn {
                let saved = UserDefaults.standard.integer(forKey: "savedScreenSaverInterval")
                let interval = saved > 0 ? saved : 300
                _ = Shell.run("defaults -currentHost write com.apple.screensaver idleTime -int \(interval)")
            } else {
                let current = Int(Shell.run("defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null")) ?? 300
                if current > 0 {
                    UserDefaults.standard.set(current, forKey: "savedScreenSaverInterval")
                }
                _ = Shell.run("defaults -currentHost write com.apple.screensaver idleTime -int 0")
            }
            
        case .nightShift:
            NightShiftService.shared.setEnabled(isOn)
            
        case .autohideDock:
            _ = Shell.run("defaults write com.apple.dock autohide -bool \(isOn); killall Dock")
            
        case .autohideMenuBar:
            setMenuBarAutoHide(isOn)
            
        case .hiddenFiles:
            _ = Shell.run("defaults write com.apple.Finder AppleShowAllFiles -bool \(isOn); killall Finder")
            
        case .lockKeyboard:
            DispatchQueue.main.async {
                KeyboardLockService.shared.setLocked(isOn)
            }
            
        case .cameraPreview:
            DispatchQueue.main.async {
                CameraPreviewService.shared.setEnabled(isOn)
            }
            
        case .timer:
            DispatchQueue.main.async {
                CountdownTimerService.shared.setEnabled(isOn)
            }
            
        case .amphetamine:
            DispatchQueue.main.async {
                AmphetamineService.shared.setEnabled(isOn)
            }
            
        case .mouseJiggler:
            DispatchQueue.main.async {
                MouseJigglerService.shared.setEnabled(isOn)
            }
            
        case .googlyEyes:
            DispatchQueue.main.async {
                GooglyEyesService.shared.setEnabled(isOn)
            }
            
        case .volumeBoost:
            DispatchQueue.main.async {
                if isOn {
                    VolumeBoostService.shared.start()
                } else {
                    VolumeBoostService.shared.stop()
                }
            }
            
        case .systemMonitor:
            DispatchQueue.main.async {
                SystemMonitorService.shared.setEnabled(isOn)
            }
            
        case .loomRecorder:
            DispatchQueue.main.async {
                LoomRecorderService.shared.setEnabled(isOn)
            }
            
        case .lockScreen:
            _ = Shell.run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend || pmset displaysleepnow")
            
        case .emptyTrash:
            _ = Shell.run("rm -rf ~/.Trash/* 2>/dev/null")
            
        case .forceQuitApps:
            if isOn {
                let quittedCount = forceQuitAllApps()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("SwitchForceQuitDidComplete"),
                        object: quittedCount
                    )
                }
            }
            
        case .autoVPN:
            DispatchQueue.main.async {
                VPNService.shared.setEnabled(isOn)
            }
            
        case .tidyFolders:
            if isOn {
                DispatchQueue.main.async {
                    FolderTidyService.shared.tidyUpAll()
                }
            }
            
        case .adblockDNS:
            DispatchQueue.main.async {
                DNSService.shared.setEnabled(isOn)
            }
            
        case .knockScreenshot:
            DispatchQueue.main.async {
                KnockScreenshotService.shared.setEnabled(isOn)
            }
            
        case .clipboardManager:
            DispatchQueue.main.async {
                ClipboardService.shared.setEnabled(isOn)
            }
            
        case .autoScroll:
            DispatchQueue.main.async {
                AutoScrollService.shared.setEnabled(isOn)
            }
            
        case .stickyNotes:
            DispatchQueue.main.async {
                StickyNotesService.shared.setVisibility(isOn)
            }
            
        case .selfControl:
            DispatchQueue.main.async {
                SelfControlService.shared.setShield(isOn)
            }
            
        case .locationServices:
            LocationService.shared.toggle(targetState: isOn)
            
        case .ramGpuReset:
            DispatchQueue.main.async {
                RAMGPUResetService.shared.setAutoGuardEnabled(isOn)
                if isOn {
                    RAMGPUResetService.shared.triggerInstantReset()
                }
            }
        }
    }
    
    // MARK: - Menu Bar AutoHide Helper (SkyLight CGS Private APIs)
    
    private typealias CGSMainConnectionID_t = @convention(c) () -> Int32
    private typealias CGSSetMenuBarAutohideEnabled_t = @convention(c) (Int32, Bool) -> Void
    private typealias CGSGetMenuBarAutohideEnabled_t = @convention(c) (Int32, UnsafeMutablePointer<Bool>) -> Void

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        return dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    }()
    
    private static let cgsMainConnectionID: CGSMainConnectionID_t? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: CGSMainConnectionID_t.self)
    }()
    
    private static let cgsSetMenuBarAutohide: CGSSetMenuBarAutohideEnabled_t? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "CGSSetMenuBarAutohideEnabled") else { return nil }
        return unsafeBitCast(sym, to: CGSSetMenuBarAutohideEnabled_t.self)
    }()
    
    private static let cgsGetMenuBarAutohide: CGSGetMenuBarAutohideEnabled_t? = {
        guard let handle = skyLightHandle, let sym = dlsym(handle, "CGSGetMenuBarAutohideEnabled") else { return nil }
        return unsafeBitCast(sym, to: CGSGetMenuBarAutohideEnabled_t.self)
    }()

    public func getMenuBarAutoHideMode() -> MenuBarAutoHideMode {
        let hideOnDesktop: Bool
        if let getFunc = Self.cgsGetMenuBarAutohide, let connFunc = Self.cgsMainConnectionID {
            var isHidden = false
            getFunc(connFunc(), &isHidden)
            hideOnDesktop = isHidden
        } else if let val = CFPreferencesCopyAppValue("_HIHideMenuBar" as CFString, kCFPreferencesAnyApplication) {
            if let boolVal = val as? Bool {
                hideOnDesktop = boolVal
            } else if let numVal = val as? NSNumber {
                hideOnDesktop = numVal.boolValue
            } else {
                hideOnDesktop = false
            }
        } else {
            let val = Shell.run("defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null")
            hideOnDesktop = (val == "1" || val.lowercased() == "true")
        }
        
        let visibleInFullscreen: Bool
        if let val = CFPreferencesCopyAppValue("AppleMenuBarVisibleInFullscreen" as CFString, kCFPreferencesAnyApplication) {
            if let boolVal = val as? Bool {
                visibleInFullscreen = boolVal
            } else if let numVal = val as? NSNumber {
                visibleInFullscreen = numVal.boolValue
            } else {
                visibleInFullscreen = false
            }
        } else {
            let val = Shell.run("defaults read NSGlobalDomain AppleMenuBarVisibleInFullscreen 2>/dev/null")
            visibleInFullscreen = (val == "1" || val.lowercased() == "true")
        }
        
        switch (hideOnDesktop, visibleInFullscreen) {
        case (true, false):
            return .always
        case (true, true):
            return .desktopOnly
        case (false, false):
            return .fullScreenOnly
        case (false, true):
            return .never
        }
    }

    private func getMenuBarAutoHide() -> Bool {
        return getMenuBarAutoHideMode().hideOnDesktop
    }

    public func setMenuBarAutoHideMode(_ mode: MenuBarAutoHideMode) {
        let hideOnDesktop = mode.hideOnDesktop
        let visibleInFullscreen = mode.visibleInFullscreen
        let ccOption = mode.controlCenterOption
        
        // 1. Immediately notify WindowServer via SkyLight
        if let setFunc = Self.cgsSetMenuBarAutohide, let connFunc = Self.cgsMainConnectionID {
            setFunc(connFunc(), hideOnDesktop)
        }
        
        // 2. Persist in preferences
        let hideVal: CFPropertyList = (hideOnDesktop ? kCFBooleanTrue : kCFBooleanFalse) as CFPropertyList
        let fullscreenVal: CFPropertyList = (visibleInFullscreen ? kCFBooleanTrue : kCFBooleanFalse) as CFPropertyList
        let ccVal: CFPropertyList = ccOption as CFNumber
        
        CFPreferencesSetValue("_HIHideMenuBar" as CFString, hideVal, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue("AppleMenuBarVisibleInFullscreen" as CFString, fullscreenVal, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue("AutoHideMenuBarOption" as CFString, ccVal, "com.apple.controlcenter" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize("com.apple.controlcenter" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        _ = Shell.run("defaults write NSGlobalDomain _HIHideMenuBar -bool \(hideOnDesktop)")
        _ = Shell.run("defaults write .GlobalPreferences _HIHideMenuBar -bool \(hideOnDesktop)")
        _ = Shell.run("defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool \(visibleInFullscreen)")
        _ = Shell.run("defaults write .GlobalPreferences AppleMenuBarVisibleInFullscreen -bool \(visibleInFullscreen)")
        _ = Shell.run("defaults write com.apple.controlcenter AutoHideMenuBarOption -int \(ccOption)")
        
        // 3. Broadcast distributed notifications
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleInterfaceFullScreenMenuBarVisibilityChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("AppleInterfaceMenuBarHidingChangedNotification" as CFString),
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("AppleInterfaceFullScreenMenuBarVisibilityChangedNotification" as CFString),
            nil,
            nil,
            true
        )
        
        // 4. Notify app listeners
        NotificationCenter.default.post(name: .menuBarAutoHideModeDidChange, object: mode)
    }

    private func setMenuBarAutoHide(_ isOn: Bool) {
        if isOn {
            setMenuBarAutoHideMode(.always)
        } else {
            setMenuBarAutoHideMode(.fullScreenOnly)
        }
    }
    
    public func triggerAction(for type: SwitchType) {
        switch type {
        case .screenSaver:
            _ = Shell.run("open -a ScreenSaverEngine")
        case .lockScreen:
            _ = Shell.run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend || pmset displaysleepnow")
        case .emptyTrash:
            _ = Shell.run("rm -rf ~/.Trash/* 2>/dev/null")
        case .forceQuitApps:
            let quittedCount = forceQuitAllApps()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("SwitchForceQuitDidComplete"),
                    object: quittedCount
                )
            }
        case .autoVPN:
            DispatchQueue.main.async {
                VPNService.shared.toggleConnection()
            }
        case .tidyFolders:
            DispatchQueue.main.async {
                FolderTidyService.shared.tidyUpAll()
            }
        case .adblockDNS:
            DispatchQueue.main.async {
                DNSService.shared.toggle()
            }
        case .knockScreenshot:
            DispatchQueue.main.async {
                KnockScreenshotService.shared.takeScreenshotNow()
            }
        case .clipboardManager:
            DispatchQueue.main.async {
                ClipboardService.shared.toggleWindow()
            }
        case .selfControl:
            DispatchQueue.main.async {
                SelfControlWindowManager.shared.showWindow()
            }
        case .ramGpuReset:
            DispatchQueue.main.async {
                RAMGPUResetService.shared.triggerInstantReset()
            }
        default:
            break
        }
    }
    
    // MARK: - Force Quit Helper
    
    public func getRunningUserApps() -> [NSRunningApplication] {
        let workspace = NSWorkspace.shared
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return workspace.runningApplications.filter { app in
            guard app.activationPolicy == .regular else { return false }
            guard app.processIdentifier != currentPID else { return false }
            guard let bundleID = app.bundleIdentifier else { return false }
            
            let protectedIDs: Set<String> = [
                "com.armank.switch",
                "com.apple.finder",
                "com.google.antigravity",
                Bundle.main.bundleIdentifier ?? ""
            ]
            return !protectedIDs.contains(bundleID)
        }
    }
    
    @discardableResult
    public func forceQuitAllApps() -> Int {
        let apps = getRunningUserApps()
        var count = 0
        for app in apps {
            let success = app.forceTerminate()
            if !success {
                kill(app.processIdentifier, SIGKILL)
            }
            count += 1
        }
        return count
    }
}
