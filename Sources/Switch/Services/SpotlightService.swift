import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import AppKit

public final class SpotlightService: @unchecked Sendable {
    public static let shared = SpotlightService()
    
    private let domainIdentifier = "com.armank.switch.switches"
    
    private init() {}
    
    /// Indexes all available switches in CoreSpotlight and generates lightweight app launchers in ~/Applications
    public func indexAllSwitches() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            self.indexCoreSpotlightItems()
            self.generateSpotlightLaunchers()
        }
    }
    
    // MARK: - CoreSpotlight Indexing
    
    private func indexCoreSpotlightItems() {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        
        var searchableItems: [CSSearchableItem] = []
        
        for type in SwitchType.allCases {
            let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
            attributeSet.title = "\(type.title) - Switch"
            attributeSet.displayName = type.title
            attributeSet.contentDescription = self.description(for: type)
            attributeSet.keywords = self.keywords(for: type) + [type.title, "Switch", "Toggle", "Mac Settings"]
            
            // Link direct custom URL scheme
            let urlString = "switch://toggle/\(type.rawValue)"
            attributeSet.url = URL(string: urlString)
            
            let item = CSSearchableItem(
                uniqueIdentifier: urlString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributeSet
            )
            // Long expiration
            item.expirationDate = Date.distantFuture
            searchableItems.append(item)
        }
        
        CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
            if let error = error {
                NSLog("[SpotlightService] CoreSpotlight indexing error: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Fast Native Spotlight Launcher Apps (~/Applications)
    
    private func generateSpotlightLaunchers() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let appsDir = homeDir.appendingPathComponent("Applications", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
        } catch {
            return
        }
        
        for type in SwitchType.allCases {
            let cleanTitle = type.title.replacingOccurrences(of: "/", with: "-")
            let appName = "\(cleanTitle).app"
            let appURL = appsDir.appendingPathComponent(appName, isDirectory: true)
            let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
            let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
            let resURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
            
            do {
                try FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: resURL, withIntermediateDirectories: true)
                
                // Copy AppIcon if available
                if let mainIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                    let dest = resURL.appendingPathComponent("AppIcon.icns")
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.copyItem(at: mainIcon, to: dest)
                    }
                }
                
                // Write fast runner executable
                let execURL = macosURL.appendingPathComponent("SwitchRunner")
                let scriptContent = """
                #!/bin/sh
                open -g "switch://toggle/\(type.rawValue)"
                """
                try scriptContent.write(to: execURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)
                
                // Write Info.plist
                let plistContent = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>CFBundleExecutable</key>
                    <string>SwitchRunner</string>
                    <key>CFBundleIdentifier</key>
                    <string>com.armank.switch.action.\(type.rawValue)</string>
                    <key>CFBundleName</key>
                    <string>\(cleanTitle)</string>
                    <key>CFBundleDisplayName</key>
                    <string>\(cleanTitle)</string>
                    <key>CFBundlePackageType</key>
                    <string>APPL</string>
                    <key>CFBundleShortVersionString</key>
                    <string>1.0</string>
                    <key>CFBundleVersion</key>
                    <string>1</string>
                    <key>CFBundleIconFile</key>
                    <string>AppIcon</string>
                    <key>LSUIElement</key>
                    <true/>
                    <key>LSMinimumSystemVersion</key>
                    <string>13.0</string>
                </dict>
                </plist>
                """
                let plistURL = contentsURL.appendingPathComponent("Info.plist")
                try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
        }
    }
    
    // MARK: - Metadata Descriptions & Keywords
    
    private func description(for type: SwitchType) -> String {
        switch type {
        case .hideDesktop: return "Instantly hide or show desktop files and folders"
        case .keepAwake: return "Prevent your Mac display and system from sleeping"
        case .screenSaver: return "Immediately start the macOS screen saver"
        case .nightShift: return "Toggle Night Shift display color temperature"
        case .autohideDock: return "Automatically show or hide the macOS Dock"
        case .autohideMenuBar: return "Automatically show or hide the top menu bar"
        case .hiddenFiles: return "Toggle display of hidden files and dotfiles in Finder"
        case .lockKeyboard: return "Lock keyboard keys for cleaning or cat prevention"
        case .cameraPreview: return "Open live selfie camera preview mirror"
        case .timer: return "Start countdown timer and alert"
        case .amphetamine: return "Keep Mac awake even when the MacBook lid is closed"
        case .mouseJiggler: return "Automatically move cursor to prevent idle state"
        case .autoScroll: return "Smooth automatic hands-free document and web page scrolling"
        case .googlyEyes: return "Playful eyes that track your cursor on screen"
        case .volumeBoost: return "Boost Mac audio volume up to 200%"
        case .autoWallpaper: return "Cycle fresh high-resolution wallpapers automatically"
        case .systemMonitor: return "Live Activity Monitor stats: CPU, RAM, Network, Battery"
        case .loomRecorder: return "Quick screen recorder with face bubble and mic"
        case .lockScreen: return "Instantly lock your Mac screen"
        case .emptyTrash: return "Permanently delete files in Trash"
        case .forceQuitApps: return "Force terminate background non-system applications"
        case .autoVPN: return "Connect or disconnect secure VPN network tunnel"
        case .tidyFolders: return "Organize Downloads and Desktop files into categorized folders"
        case .adblockDNS: return "Toggle AdBlock & Malware protective encrypted DNS"
        case .knockScreenshot: return "Double-knock Mac chassis to take instant screenshot"
        case .clipboardManager: return "View and search clipboard copy history"
        case .stickyNotes: return "Create persistent desktop sticky notes with checklists"
        case .locationServices: return "Quick toggle for Location Services"
        case .ramGpuReset: return "Purge memory cache, flush inactive RAM and GPU context"
        case .cleanMacCache: return "Scan and purge caches, temp files, and junk logs"
        case .wisprFlow: return "AI speech-to-text voice dictation into active app"
        case .dockDoor: return "Window hover preview thumbnails when mousing over Dock icons"
        case .mouseBoostPro: return "Optimize mouse tracking and disable acceleration"
        case .ultraPowerSave: return "Throttle energy, reduce brightness, switch Mac to low power mode"
        case .textGrabber: return "Select area to grab text from images or video into clipboard"
        }
    }
    
    private func keywords(for type: SwitchType) -> [String] {
        switch type {
        case .hideDesktop: return ["desktop", "icons", "clean", "hide"]
        case .keepAwake: return ["caffeine", "sleep", "awake", "screen", "stay"]
        case .screenSaver: return ["screensaver", "saver", "idle", "display"]
        case .nightShift: return ["blue", "warm", "orange", "night", "dark", "display", "eyes"]
        case .autohideDock: return ["dock", "bar", "hide dock", "auto hide"]
        case .autohideMenuBar: return ["menubar", "menu bar", "top bar", "hide menubar"]
        case .hiddenFiles: return ["dotfiles", "hidden", "finder", "show files", "secret"]
        case .lockKeyboard: return ["keyboard", "keys", "cleaning", "cat", "lock keys"]
        case .cameraPreview: return ["webcam", "camera", "video", "mirror", "selfie"]
        case .timer: return ["countdown", "alarm", "stopwatch", "clock", "remind"]
        case .amphetamine: return ["lid", "clamshell", "keep awake", "macbook closed", "sleep"]
        case .mouseJiggler: return ["mouse", "jiggle", "mover", "cursor", "afk", "slack", "teams"]
        case .autoScroll: return ["scroll", "reading", "handsfree", "autoscroll", "page"]
        case .googlyEyes: return ["eyes", "cursor follow", "fun", "pupils", "look"]
        case .volumeBoost: return ["sound", "audio", "speaker", "loud", "amplifier", "boost", "200%"]
        case .systemMonitor: return ["activity monitor", "cpu", "ram", "memory", "battery", "disk", "stats", "hardware"]
        case .loomRecorder: return ["screen recording", "record", "loom", "video", "capture", "mic"]
        case .forceQuitApps: return ["kill", "quit", "close all", "task manager", "exit apps"]
        case .autoVPN: return ["vpn", "tunnel", "privacy", "secure", "proxy", "network"]
        case .tidyFolders: return ["cleanup", "organize", "downloads", "desktop", "sort"]
        case .adblockDNS: return ["dns", "adblock", "privacy", "block ads", "cloudflare", "quad9"]
        case .knockScreenshot: return ["screenshot", "snip", "capture", "screen", "knock"]
        case .clipboardManager: return ["clipboard", "history", "copy", "paste", "snippets"]
        case .stickyNotes: return ["notes", "sticky", "memo", "todo", "post it"]
        case .locationServices: return ["gps", "location", "privacy", "where", "tracking"]
        case .ramGpuReset: return ["ram clean", "purge", "memory leak", "free ram", "flush"]
        case .cleanMacCache: return ["cache", "clean disk", "free space", "junk", "logs", "storage"]
        case .autoWallpaper: return ["wallpaper", "background", "desktop image", "unsplash", "theme"]
        case .wisprFlow: return ["voice", "dictation", "transcribe", "speech", "whisper", "ai typing"]
        case .dockDoor: return ["window preview", "dock peek", "thumbnails", "alt tab"]
        case .mouseBoostPro: return ["mouse acceleration", "gaming", "smooth cursor", "dpi", "speed"]
        case .ultraPowerSave: return ["battery saver", "eco", "low power", "throttle", "save battery"]
        case .textGrabber: return ["ocr", "copy text", "extract text", "image text", "video text"]
        default: return []
        }
    }
}

