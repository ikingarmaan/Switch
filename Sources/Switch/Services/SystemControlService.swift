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
    case grammarCoach = "grammarCoach"
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
        case .grammarCoach: return "Grammar Coach"
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
        case .grammarCoach: return "character.cursor.ibeam"
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

public final class SystemControlService: @unchecked Sendable {
    public static let shared = SystemControlService()
    
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
            return (NightShiftService.shared.isEnabled(), nil)
            
        case .autohideDock:
            let val = Shell.run("defaults read com.apple.dock autohide 2>/dev/null")
            return (val == "1" || val.lowercased() == "true", nil)
            
        case .autohideMenuBar:
            return (getMenuBarAutoHide(), nil)
            
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
            let sub = m.isActive ? m.formattedRemainingTime : m.formattedSelectedDuration
            return (m.isActive, sub)
            
        case .googlyEyes:
            let g = GooglyEyesService.shared
            return (g.isEnabled, g.isEnabled ? g.currentEmotion.label : nil)
            
        case .volumeBoost:
            let v = VolumeBoostService.shared
            return (v.isActive, v.isActive ? v.selectedLevel.label : nil)
            
        case .grammarCoach:
            let coach = GrammarCoachService.shared
            return (coach.isEnabled, coach.isEnabled ? coach.currentStyle.rawValue : nil)
            
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
            
        case .grammarCoach:
            DispatchQueue.main.async {
                GrammarCoachService.shared.setEnabled(isOn)
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
        }
    }
    
    // MARK: - Menu Bar AutoHide Helper
    
    private func getMenuBarAutoHide() -> Bool {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync { [weak self] in
                return self?.getMenuBarAutoHide() ?? false
            }
        }
        
        let script = "tell application \"System Events\" to tell dock preferences to get autohide menu bar"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&error)
            if error == nil {
                return descriptor.booleanValue
            }
        }
        let val = Shell.run("defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null")
        return val == "1" || val.lowercased() == "true"
    }

    private func setMenuBarAutoHide(_ isOn: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { [weak self] in
                self?.setMenuBarAutoHide(isOn)
            }
            return
        }
        
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        _ = AEDeterminePermissionToAutomateTarget(
            targetDesc.aeDesc,
            OSType(typeWildCard),
            OSType(typeWildCard),
            true
        )
        
        let script = "tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(isOn)"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript error for autohideMenuBar: \(err)")
                if let code = err["NSAppleScriptErrorNumber"] as? Int, code == -1743 {
                    let alert = NSAlert()
                    alert.messageText = "Automation Permission Required"
                    alert.informativeText = "Switch requires permission to control System Events in order to automatically hide and show the menu bar.\n\nPlease enable System Events under Switch in System Settings > Privacy & Security > Automation."
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        _ = Shell.run("defaults write NSGlobalDomain _HIHideMenuBar -bool \(isOn)")
        _ = Shell.run("defaults write .GlobalPreferences AppleMenuBarVisibleInFullscreen -bool \(!isOn)")
    }
    
    public func triggerAction(for type: SwitchType) {
        switch type {
        case .screenSaver:
            _ = Shell.run("open -a ScreenSaverEngine")
        case .lockScreen:
            _ = Shell.run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend || pmset displaysleepnow")
        case .emptyTrash:
            _ = Shell.run("rm -rf ~/.Trash/* 2>/dev/null")
        case .grammarCoach:
            DispatchQueue.main.async {
                GrammarCoachService.shared.showTypingBox()
            }
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
