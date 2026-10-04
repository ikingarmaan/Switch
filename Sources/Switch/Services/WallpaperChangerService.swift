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
    case allPictures = "allPictures"
    case macDefault = "macDefault"
    case userWallpapers = "userWallpapers"
    case customFolder = "customFolder"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .allPictures: return "🖼️ All Pictures & Wallpapers (System + Finder)"
        case .macDefault: return "🍏 Mac System Wallpapers"
        case .userWallpapers: return "📁 User Wallpapers (~/Pictures/Wallpapers)"
        case .customFolder: return "📂 Choose Custom Folder..."
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .allPictures: return "All Pictures"
        case .macDefault: return "System Wallpapers"
        case .userWallpapers: return "User Wallpapers"
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
    
    private static var singleColorCache: [String: Bool] = [:]
    private static let cacheLock = NSLock()
    
    /// Checks and detects whether an image is a single/solid color image or system thumbnail to exclude it
    public static func isSingleColorImage(_ url: URL) -> Bool {
        let path = url.path
        
        cacheLock.lock()
        if let cached = singleColorCache[path] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let result = evaluateIsSingleColorImage(url)
        
        cacheLock.lock()
        singleColorCache[path] = result
        cacheLock.unlock()
        
        return result
    }
    
    private static func evaluateIsSingleColorImage(_ url: URL) -> Bool {
        let pathLower = url.path.lowercased()
        let nameLower = url.lastPathComponent.lowercased()
        
        // Exclude directories / files matching solid color keywords
        if pathLower.contains("solid color") || pathLower.contains("solid_color") || pathLower.contains("solidcolors") || pathLower.contains("/solid/") || pathLower.contains("/solid colors/") || pathLower.contains("single color") {
            return true
        }
        
        // Exclude system thumbnail png previews (e.g. Sonoma Horizon Thumbnail.png)
        if nameLower.contains("thumbnail") && (nameLower.hasSuffix(".png") || nameLower.hasSuffix(".jpg")) {
            return true
        }
        
        // Check file size: tiny files (< 20 KB) are solid swatches / placeholders
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? Int64, fileSize < 20_000 {
            return true
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return true
        }
        
        // Too small resolution to be a proper photo wallpaper
        if cgImage.width <= 64 || cgImage.height <= 64 {
            return true
        }
        
        // Downsample to an 8x8 sRGB grid (64 sample pixels) to compute color variance
        let width = 8
        let height = 8
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rawData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return false
        }
        
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var minR = 255, maxR = 0
        var minG = 255, maxG = 0
        var minB = 255, maxB = 0
        
        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let r = Int(rawData[i])
            let g = Int(rawData[i + 1])
            let b = Int(rawData[i + 2])
            
            if r < minR { minR = r }
            if r > maxR { maxR = r }
            if g < minG { minG = g }
            if g > maxG { maxG = g }
            if b < minB { minB = b }
            if b > maxB { maxB = b }
        }
        
        let deltaR = maxR - minR
        let deltaG = maxG - minG
        let deltaB = maxB - minB
        let maxDelta = max(deltaR, deltaG, deltaB)
        
        // If color variation across the entire image is <= 8, it's a solid single color!
        return maxDelta <= 8
    }
    
    /// Strict quality gate: Only allow true High-Definition / 4K / 5K / 6K / 8K wallpapers (min 1920x1080)
    public static func isHighResolutionWallpaper(_ url: URL) -> Bool {
        let pathLower = url.path.lowercased()
        let nameLower = url.lastPathComponent.lowercased()
        
        if pathLower.contains(".thumbnails") || pathLower.contains("/thumbnails/") || pathLower.contains("solid color") {
            return false
        }
        if nameLower.contains("thumbnail") {
            return false
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return false
        }
        
        let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
        
        // Must be at least 1080p Full HD (1920x1080 or 1080x1920)
        let isFullHDLandscape = width >= 1920 && height >= 1080
        let isFullHDPortrait = width >= 1080 && height >= 1920
        guard isFullHDLandscape || isFullHDPortrait else {
            return false
        }
        
        return !isSingleColorImage(url)
    }
    
    private func scanDirectory(at path: String, extensions: Set<String>, recursive: Bool = false) -> [URL] {
        var results: [URL] = []
        guard FileManager.default.fileExists(atPath: path) else { return results }
        
        let rootURL = URL(fileURLWithPath: path)
        if recursive {
            if let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.path.contains(".thumbnails") { continue }
                    let ext = fileURL.pathExtension.lowercased()
                    if extensions.contains(ext) {
                        if Self.isHighResolutionWallpaper(fileURL) {
                            results.append(fileURL)
                        }
                    }
                }
            }
        } else {
            if let direct = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for fileURL in direct {
                    let ext = fileURL.pathExtension.lowercased()
                    if extensions.contains(ext) {
                        if Self.isHighResolutionWallpaper(fileURL) {
                            results.append(fileURL)
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    public func reloadWallpaperList() {
        let extensions: Set<String> = ["heic", "jpg", "jpeg", "png", "webp", "tiff", "tif"]
        var scannedURLs: [URL] = []
        
        let systemDirs = [
            Self.macDefaultWallpapersPath,
            "\(Self.macDefaultWallpapersPath)/.wallpapers/Sonoma Horizon",
            "/Library/Desktop Pictures"
        ]
        
        let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? "\(NSHomeDirectory())/Pictures"
        let desktopDir = "\(NSHomeDirectory())/Desktop"
        
        switch source {
        case .allPictures:
            // Combine all full 5K/6K macOS system wallpapers + 4K/8K user wallpapers & pictures!
            for sys in systemDirs {
                scannedURLs.append(contentsOf: scanDirectory(at: sys, extensions: extensions, recursive: false))
            }
            ensureUserWallpapersDirectoryExists()
            scannedURLs.append(contentsOf: scanDirectory(at: userWallpapersPath, extensions: extensions, recursive: true))
            scannedURLs.append(contentsOf: scanDirectory(at: picturesDir, extensions: extensions, recursive: true))
            scannedURLs.append(contentsOf: scanDirectory(at: desktopDir, extensions: extensions, recursive: true))
            if !customFolderPath.isEmpty {
                scannedURLs.append(contentsOf: scanDirectory(at: customFolderPath, extensions: extensions, recursive: true))
            }
            
        case .macDefault:
            for sys in systemDirs {
                scannedURLs.append(contentsOf: scanDirectory(at: sys, extensions: extensions, recursive: false))
            }
            
        case .userWallpapers:
            ensureUserWallpapersDirectoryExists()
            scannedURLs.append(contentsOf: scanDirectory(at: userWallpapersPath, extensions: extensions, recursive: true))
            scannedURLs.append(contentsOf: scanDirectory(at: picturesDir, extensions: extensions, recursive: true))
            
        case .customFolder:
            let folder = customFolderPath.isEmpty ? userWallpapersPath : customFolderPath
            scannedURLs.append(contentsOf: scanDirectory(at: folder, extensions: extensions, recursive: true))
        }
        
        // Deduplicate wallpapers by unique base name
        var seenNames = Set<String>()
        var uniqueURLs: [URL] = []
        
        for url in scannedURLs {
            let baseName = url.deletingPathExtension().lastPathComponent
            if !seenNames.contains(baseName) {
                seenNames.insert(baseName)
                uniqueURLs.append(url)
            }
        }
        
        // Fallback to system wallpapers if empty
        if uniqueURLs.isEmpty {
            for sys in systemDirs {
                uniqueURLs.append(contentsOf: scanDirectory(at: sys, extensions: extensions, recursive: false))
            }
        }
        
        self.availableWallpapers = uniqueURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        self.totalWallpapersCount = uniqueURLs.count
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
