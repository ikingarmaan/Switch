import Cocoa
import SwiftUI

public extension Notification.Name {
    static let wallpaperChangerStateDidChange = Notification.Name("SwitchWallpaperChangerStateDidChange")
    static let wallpaperDidChange = Notification.Name("SwitchWallpaperDidChange")
}

public enum WallpaperInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneMin = 60
    case fiveMin = 300
    case tenMin = 600
    case fifteenMin = 900
    case thirtyMin = 1800
    case oneHour = 3600
    case twoHours = 7200
    case daily = 86400
    
    public var id: Int { rawValue }
    
    public var label: String {
        switch self {
        case .oneMin: return "1 Minute (⚡️ Fast)"
        case .fiveMin: return "5 Minutes (Default)"
        case .tenMin: return "10 Minutes"
        case .fifteenMin: return "15 Minutes"
        case .thirtyMin: return "30 Minutes"
        case .oneHour: return "1 Hour"
        case .twoHours: return "2 Hours"
        case .daily: return "Daily"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .oneMin: return "1 min"
        case .fiveMin: return "5 min"
        case .tenMin: return "10 min"
        case .fifteenMin: return "15 min"
        case .thirtyMin: return "30 min"
        case .oneHour: return "1 hr"
        case .twoHours: return "2 hr"
        case .daily: return "Daily"
        }
    }
}

public enum WallpaperSource: String, CaseIterable, Identifiable, Sendable {
    case macDefault = "macDefault"
    case userWallpapers = "userWallpapers"
    case allPictures = "allPictures"
    case customFolder = "customFolder"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .macDefault: return "🍏 Mac Default Wallpapers"
        case .userWallpapers: return "📁 User Wallpapers (~/Pictures/Wallpapers)"
        case .allPictures: return "🖼️ All Pictures (~/Pictures)"
        case .customFolder: return "📂 Choose Custom Folder..."
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .macDefault: return "Default Wallpapers"
        case .userWallpapers: return "User Wallpapers"
        case .allPictures: return "Pictures"
        case .customFolder: return "Custom Folder"
        }
    }
}

public enum WallpaperOrderMode: String, CaseIterable, Identifiable, Sendable {
    case shuffle = "Shuffle (Random)"
    case sequential = "Sequential (In Order)"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .shuffle: return "shuffle"
        case .sequential: return "arrow.triangle.2.circlepath"
        }
    }
}

public final class WallpaperChangerService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = WallpaperChangerService()
    
    private let keyEnabled = "Switch_WallpaperChanger_Enabled"
    private let keyInterval = "Switch_WallpaperChanger_Interval"
    private let keySource = "Switch_WallpaperChanger_Source"
    private let keyOrderMode = "Switch_WallpaperChanger_OrderMode"
    private let keyCustomPath = "Switch_WallpaperChanger_CustomPath"
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public var interval: WallpaperInterval = .fiveMin {
        didSet {
            UserDefaults.standard.set(interval.rawValue, forKey: keyInterval)
            if isEnabled {
                restartTimer()
            }
        }
    }
    @Published public var source: WallpaperSource = .macDefault {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: keySource)
            reloadWallpaperList()
        }
    }
    @Published public var orderMode: WallpaperOrderMode = .shuffle {
        didSet {
            UserDefaults.standard.set(orderMode.rawValue, forKey: keyOrderMode)
        }
    }
    @Published public var customFolderPath: String = "" {
        didSet {
            UserDefaults.standard.set(customFolderPath, forKey: keyCustomPath)
            if source == .customFolder {
                reloadWallpaperList()
            }
        }
    }
    
    @Published public private(set) var currentWallpaperName: String? = nil
    @Published public private(set) var totalWallpapersCount: Int = 0
    @Published public private(set) var currentIndex: Int = 0
    
    private var timer: Timer?
    private var availableWallpapers: [URL] = []
    
    public static let macDefaultWallpapersPath = "/System/Library/Desktop Pictures"
    
    public var userWallpapersPath: String {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? ("\(NSHomeDirectory())/Pictures")
        return "\(pictures)/Wallpapers"
    }
    
    public var statusSubtitle: String? {
        guard isEnabled else { return nil }
        let countText = totalWallpapersCount > 0 ? "\(totalWallpapersCount) Photos" : source.shortTitle
        return "\(interval.shortLabel) · \(countText)"
    }
    
    private override init() {
        super.init()
        let savedEnabled = UserDefaults.standard.bool(forKey: keyEnabled)
        let savedInterval = UserDefaults.standard.integer(forKey: keyInterval)
        if savedInterval > 0, let val = WallpaperInterval(rawValue: savedInterval) {
            self.interval = val
        } else {
            self.interval = .fiveMin
        }
        
        let savedSource = UserDefaults.standard.string(forKey: keySource) ?? WallpaperSource.macDefault.rawValue
        self.source = WallpaperSource(rawValue: savedSource) ?? .macDefault
        
        let savedOrder = UserDefaults.standard.string(forKey: keyOrderMode) ?? WallpaperOrderMode.shuffle.rawValue
        self.orderMode = WallpaperOrderMode(rawValue: savedOrder) ?? .shuffle
        
        self.customFolderPath = UserDefaults.standard.string(forKey: keyCustomPath) ?? ""
        
        ensureUserWallpapersDirectoryExists()
        reloadWallpaperList()
        
        if savedEnabled {
            setEnabled(true)
        }
    }
    
    public func ensureUserWallpapersDirectoryExists() {
        let path = userWallpapersPath
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: keyEnabled)
        
        if enabled {
            reloadWallpaperList()
            nextWallpaper(notify: false)
            restartTimer()
            playTickSound()
        } else {
            stopTimer()
        }
        
        NotificationCenter.default.post(name: .wallpaperChangerStateDidChange, object: enabled)
    }
    
    public func setInterval(_ newInterval: WallpaperInterval) {
        self.interval = newInterval
        playTickSound()
    }
    
    public func setSource(_ newSource: WallpaperSource) {
        if newSource == .customFolder && customFolderPath.isEmpty {
            selectCustomFolder()
        } else {
            self.source = newSource
            playTickSound()
            nextWallpaper(notify: false)
        }
    }
    
    public func setOrderMode(_ newMode: WallpaperOrderMode) {
        self.orderMode = newMode
        playTickSound()
    }
    
    public func reloadWallpaperList() {
        let extensions: Set<String> = ["heic", "jpg", "jpeg", "png", "webp", "tiff", "tif"]
        var urls: [URL] = []
        
        let folderToScan: String
        switch source {
        case .macDefault:
            folderToScan = Self.macDefaultWallpapersPath
        case .userWallpapers:
            ensureUserWallpapersDirectoryExists()
            folderToScan = userWallpapersPath
        case .allPictures:
            folderToScan = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? "\(NSHomeDirectory())/Pictures"
        case .customFolder:
            folderToScan = customFolderPath.isEmpty ? userWallpapersPath : customFolderPath
        }
        
        if FileManager.default.fileExists(atPath: folderToScan) {
            let rootURL = URL(fileURLWithPath: folderToScan)
            if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    if extensions.contains(fileURL.pathExtension.lowercased()) {
                        urls.append(fileURL)
                    }
                }
            }
            
            // Direct contents check
            if urls.isEmpty {
                if let direct = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: []) {
                    for fileURL in direct {
                        if extensions.contains(fileURL.pathExtension.lowercased()) {
                            urls.append(fileURL)
                        }
                    }
                }
            }
        }
        
        // If user folder was empty, fallback to default Mac wallpapers
        if urls.isEmpty && source != .macDefault {
            let rootURL = URL(fileURLWithPath: Self.macDefaultWallpapersPath)
            if let direct = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: []) {
                for fileURL in direct {
                    if extensions.contains(fileURL.pathExtension.lowercased()) {
                        urls.append(fileURL)
                    }
                }
            }
        }
        
        self.availableWallpapers = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        self.totalWallpapersCount = urls.count
    }
    
    public func nextWallpaper(notify: Bool = true) {
        if availableWallpapers.isEmpty {
            reloadWallpaperList()
        }
        guard !availableWallpapers.isEmpty else { return }
        
        let chosenURL: URL
        if orderMode == .shuffle {
            if availableWallpapers.count > 1, let curr = currentWallpaperName {
                let filtered = availableWallpapers.filter { $0.deletingPathExtension().lastPathComponent != curr }
                chosenURL = filtered.randomElement() ?? availableWallpapers.randomElement()!
            } else {
                chosenURL = availableWallpapers.randomElement()!
            }
        } else {
            currentIndex = (currentIndex + 1) % availableWallpapers.count
            chosenURL = availableWallpapers[currentIndex]
        }
        
        applyWallpaper(chosenURL)
        
        if notify {
            playTickSound()
        }
    }
    
    private func applyWallpaper(_ url: URL) {
        currentWallpaperName = url.deletingPathExtension().lastPathComponent
        
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        
        NotificationCenter.default.post(name: .wallpaperDidChange, object: url)
    }
    
    private func restartTimer() {
        stopTimer()
        guard isEnabled else { return }
        
        let intervalSeconds = TimeInterval(interval.rawValue)
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.nextWallpaper(notify: false)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Finder Actions
    
    public func revealDefaultWallpapersInFinder() {
        let url = URL(fileURLWithPath: Self.macDefaultWallpapersPath)
        NSWorkspace.shared.open(url)
    }
    
    public func revealUserWallpapersInFinder() {
        ensureUserWallpapersDirectoryExists()
        let path = (source == .customFolder && !customFolderPath.isEmpty) ? customFolderPath : userWallpapersPath
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    public func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Wallpapers Folder"
        panel.prompt = "Choose Folder"
        
        if panel.runModal() == .OK, let selected = panel.url {
            self.customFolderPath = selected.path
            self.source = .customFolder
            reloadWallpaperList()
            nextWallpaper(notify: true)
        }
    }
    
    private func playTickSound() {
        if AppSettings.shared.playSound {
            NSSound(named: "Tink")?.play()
        }
    }
}
