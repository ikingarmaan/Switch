import Foundation
import Cocoa
import AVFoundation
import CoreServices
import Combine
import SwiftUI

public extension Notification.Name {
    static let mediaPlayerDidChange = Notification.Name("SwitchMediaPlayerDidChange")
    static let mediaPlayerPlaybackTick = Notification.Name("SwitchMediaPlayerPlaybackTick")
}

public final class UniversalMediaPlayerService: ObservableObject, @unchecked Sendable {
    public static let shared = UniversalMediaPlayerService()
    
    // MARK: - Core AVPlayer Engine
    public private(set) var player: AVPlayer = AVPlayer()
    private var timeObserverToken: Any?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published Playback State
    @Published public var isWindowOpen: Bool = false
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var currentVolume: Float = 1.0 // 0.0 to 2.0 (0% to 200% volume boost!)
    @Published public var isMuted: Bool = false
    @Published public var playbackSpeed: Float = 1.0
    @Published public var videoTitle: String = "No Media Open"
    @Published public var currentVideoURL: URL? = nil
    @Published public var nativeVideoSize: CGSize = CGSize(width: 854, height: 480)
    
    // Playlist & Recent Files
    @Published public var playlist: [PlaylistItem] = []
    @Published public var currentPlaylistIndex: Int = 0
    @Published public var recentFiles: [URL] = []
    
    // Looping & A-B Repeat
    @Published public var isRepeatAll: Bool = false
    @Published public var isRepeatOne: Bool = false
    @Published public var abLoopPointA: TimeInterval? = nil
    @Published public var abLoopPointB: TimeInterval? = nil
    
    // Video Canvas & Aspect Ratio
    @Published public var aspectRatioMode: VideoAspectRatioMode = .original
    @Published public var isAlwaysOnTop: Bool = false
    
    // Video Adjustments (Color Equalizer)
    @Published public var brightness: Double = 0.0 // -1.0 to 1.0
    @Published public var contrast: Double = 1.0   // 0.5 to 2.0
    @Published public var saturation: Double = 1.0 // 0.0 to 2.0
    @Published public var hueRotation: Double = 0.0 // 0 to 360
    
    // Subtitle Engine
    @Published public var availableSubtitles: [SubtitleTrack] = []
    @Published public var selectedSubtitleTrack: SubtitleTrack? = nil
    @Published public var activeSubtitleCue: SubtitleCue? = nil
    @Published public var subtitleDelay: TimeInterval = 0.0
    @Published public var subtitleFontSize: CGFloat = 20.0
    @Published public var subtitleColorHex: String = "#FFFFFF"
    
    // Audio Tracks & Delay
    @Published public var availableAudioTracks: [MediaAudioTrack] = []
    @Published public var selectedAudioTrack: MediaAudioTrack? = nil
    @Published public var audioDelay: TimeInterval = 0.0
    
    // Bookmarks
    @Published public var bookmarks: [MediaBookmark] = []
    
    // Feedback & Toasts
    @Published public var statusToast: String? = nil
    @Published public var isDrawerOpen: Bool = false
    
    // Saved Playback Positions (Persistence dictionary: URL string -> timestamp)
    private var savedPositions: [String: TimeInterval] = [:]
    
    // MARK: - Initializer
    
    private init() {
        loadSavedRecentFiles()
        setupTimeObserver()
        setupAudioSessionSettings()
    }
    
    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }
    
    // MARK: - Setup AVPlayer Observers
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.onTimeUpdate(time: time)
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            self?.handleItemDidFinishPlaying()
        }
    }
    
    private func setupAudioSessionSettings() {
        player.actionAtItemEnd = .pause
    }
    
    // MARK: - Open Media Files / URLs
    
    public func openVideo(url: URL) {
        openVideos(urls: [url])
    }
    
    public func openVideos(urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        // Add to playlist
        let newItems = urls.map { PlaylistItem(url: $0) }
        self.playlist = newItems
        self.currentPlaylistIndex = 0
        
        loadCurrentPlaylistItem()
        
        // Bring player window to front
        MediaPlayerWindowManager.shared.showWindow()
        
        NotificationCenter.default.post(name: .mediaPlayerDidChange, object: nil)
    }
    
    public func openURLStream(urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        openVideo(url: url)
    }
    
    public func loadCurrentPlaylistItem() {
        guard currentPlaylistIndex >= 0 && currentPlaylistIndex < playlist.count else { return }
        let item = playlist[currentPlaylistIndex]
        let url = item.url
        
        // Save to recent files
        addToRecentFiles(url: url)
        
        self.currentVideoURL = url
        self.videoTitle = item.title
        self.currentTime = 0
        self.duration = 0
        self.abLoopPointA = nil
        self.abLoopPointB = nil
        self.activeSubtitleCue = nil
        self.availableSubtitles.removeAll()
        self.selectedSubtitleTrack = nil
        
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Configure pitch preservation for speed changing
        playerItem.audioTimePitchAlgorithm = .timeDomain
        
        player.replaceCurrentItem(with: playerItem)
        applyVolumeSettings()
        
        // Fetch track dimensions and duration asynchronously
        Task { [weak self] in
            guard let self = self else { return }
            
            if let d = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(d)
                if seconds.isFinite && seconds > 0 {
                    self.duration = seconds
                }
            }
            
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let first = tracks.first,
               let size = try? await first.load(.naturalSize),
               let transform = try? await first.load(.preferredTransform) {
                
                // Adjust for rotation transform (e.g. vertical iPhone videos)
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                let adjustedSize = CGSize(width: abs(rect.width), height: abs(rect.height))
                
                if adjustedSize.width > 0 && adjustedSize.height > 0 {
                    self.nativeVideoSize = adjustedSize
                    Task { @MainActor in
                        MediaPlayerWindowManager.shared.adjustWindowToVideoSize(adjustedSize)
                    }
                }
            }
            
            // Discover embedded and external subtitles
            self.discoverSubtitles(for: url, asset: asset)
            
            // Discover audio tracks
            self.discoverAudioTracks(asset: asset)
            
            // Check if there was a saved playback position
            if let saved = self.savedPositions[url.absoluteString], saved > 10, saved < (self.duration - 10) {
                self.seek(to: saved)
                self.showToast("Resumed from \(self.formatTime(saved))")
            }
            
            self.play()
        }
    }
    
    // MARK: - Playback Controls
    
    public func play() {
        player.rate = playbackSpeed
        isPlaying = true
        NotificationCenter.default.post(name: .mediaPlayerDidChange, object: nil)
    }
    
    public func pause() {
        player.pause()
        isPlaying = false
        NotificationCenter.default.post(name: .mediaPlayerDidChange, object: nil)
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        currentTime = clamped
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Update active subtitle cue immediately
        updateSubtitleCue(at: clamped)
    }
    
    public func stepForward(seconds: Double = 5.0) {
        seek(to: currentTime + seconds)
        showToast("+\(Int(seconds))s (\(formatTime(currentTime)))")
    }
    
    public func stepBackward(seconds: Double = 5.0) {
        seek(to: currentTime - seconds)
        showToast("-\(Int(seconds))s (\(formatTime(currentTime)))")
    }
    
    // MARK: - Volume Overdrive (0% to 200%)
    
    public func setVolume(_ vol: Float) {
        let clamped = max(0.0, min(vol, 2.0))
        self.currentVolume = clamped
        if isMuted && clamped > 0 {
            isMuted = false
        }
        applyVolumeSettings()
        
        let pct = Int(clamped * 100)
        showToast(pct > 100 ? "Volume \(pct)% (Overdrive Boost ⚡)" : "Volume \(pct)%")
    }
    
    public func adjustVolume(delta: Float) {
        setVolume(currentVolume + delta)
    }
    
    public func toggleMute() {
        isMuted.toggle()
        applyVolumeSettings()
        showToast(isMuted ? "Muted" : "Unmuted (\(Int(currentVolume * 100))%)")
    }
    
    private func applyVolumeSettings() {
        if isMuted {
            player.volume = 0.0
        } else {
            // AVPlayer natively supports volume up to 1.0. For values > 1.0 (up to 2.0 = 200%),
            // we maximize player volume and boost audioMix parameters
            player.volume = min(currentVolume, 1.0)
            
            if let item = player.currentItem {
                let mix = AVMutableAudioMix()
                let tracks = item.asset.tracks(withMediaType: .audio)
                var inputParams: [AVMutableAudioMixInputParameters] = []
                
                for track in tracks {
                    let param = AVMutableAudioMixInputParameters(track: track)
                    param.setVolume(currentVolume, at: .zero)
                    inputParams.append(param)
                }
                mix.inputParameters = inputParams
                item.audioMix = mix
            }
        }
    }
    
    // MARK: - Playback Speed
    
    public func setSpeed(_ speed: Float) {
        let clamped = max(0.25, min(speed, 3.0))
        self.playbackSpeed = clamped
        if isPlaying {
            player.rate = clamped
        }
        showToast(String(format: "Speed %.2fx", clamped))
    }
    
    public func adjustSpeed(delta: Float) {
        setSpeed(playbackSpeed + delta)
    }
    
    public func cycleSpeed() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        if let idx = speeds.firstIndex(where: { abs($0 - playbackSpeed) < 0.05 }) {
            let next = speeds[(idx + 1) % speeds.count]
            setSpeed(next)
        } else {
            setSpeed(1.0)
        }
    }
    
    // MARK: - A-B Looping (VLC Power Tool)
    
    public func handleABLoopButton() {
        if abLoopPointA == nil {
            // Set Point A
            abLoopPointA = currentTime
            showToast("Loop Point A set at \(formatTime(currentTime))")
        } else if abLoopPointB == nil {
            // Set Point B
            if currentTime > abLoopPointA! {
                abLoopPointB = currentTime
                showToast("Loop A-B Active: \(formatTime(abLoopPointA!)) ➔ \(formatTime(currentTime))")
            } else {
                showToast("Point B must be after Point A")
            }
        } else {
            // Clear Loop
            clearABLoop()
            showToast("A-B Loop Cleared")
        }
    }
    
    public func clearABLoop() {
        abLoopPointA = nil
        abLoopPointB = nil
    }
    
    // MARK: - Bookmarks
    
    public func addBookmark(title: String? = nil) {
        let name = title ?? "Bookmark at \(formatTime(currentTime))"
        let mark = MediaBookmark(timestamp: currentTime, title: name)
        bookmarks.append(mark)
        showToast("Bookmark added: \(name)")
    }
    
    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }
    
    // MARK: - High Resolution Snapshot
    
    public func takeSnapshot() {
        guard let item = player.currentItem else { return }
        let asset = item.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let targetTime = player.currentTime()
        let timestampStr = formatTime(currentTime).replacingOccurrences(of: ":", with: "-")
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let cgImage = try await generator.image(at: targetTime).image
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                
                // Copy to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([nsImage])
                
                // Save to ~/Pictures/Switch Player
                let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                let switchDir = picturesDir.appendingPathComponent("Switch Player", isDirectory: true)
                try? FileManager.default.createDirectory(at: switchDir, withIntermediateDirectories: true)
                
                let baseName = self.currentVideoURL?.deletingPathExtension().lastPathComponent ?? "Snapshot"
                let fileName = "\(baseName)_\(timestampStr)_\(Int(Date().timeIntervalSince1970)).png"
                let fileURL = switchDir.appendingPathComponent(fileName)
                
                if let tiff = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: fileURL)
                }
                
                self.showToast("📸 Snapshot Saved & Copied to Clipboard!")
            } catch {
                self.showToast("Failed to capture snapshot")
            }
        }
    }
    
    // MARK: - Subtitles Discovery & Parsing
    
    private func discoverSubtitles(for videoURL: URL, asset: AVAsset) {
        var tracks: [SubtitleTrack] = []
        
        // 1. External Subtitles in the same folder (.srt, .vtt, .ass)
        let found = SubtitleParser.shared.findSubtitles(for: videoURL)
        for url in found {
            let cues = SubtitleParser.shared.parse(fileURL: url)
            let name = url.lastPathComponent
            let track = SubtitleTrack(id: url.absoluteString, name: name, isExternal: true, cues: cues)
            tracks.append(track)
        }
        
        self.availableSubtitles = tracks
        
        // Auto-select first subtitle if available
        if let first = tracks.first {
            self.selectedSubtitleTrack = first
            self.showToast("Loaded Subtitle: \(first.name)")
        }
    }
    
    public func loadExternalSubtitle(fileURL: URL) {
        let cues = SubtitleParser.shared.parse(fileURL: fileURL)
        let track = SubtitleTrack(id: fileURL.absoluteString, name: fileURL.lastPathComponent, isExternal: true, cues: cues)
        
        availableSubtitles.removeAll { $0.id == track.id }
        availableSubtitles.insert(track, at: 0)
        selectedSubtitleTrack = track
        showToast("Subtitle Loaded: \(track.name)")
    }
    
    public func selectSubtitleTrack(_ track: SubtitleTrack?) {
        self.selectedSubtitleTrack = track
        self.activeSubtitleCue = nil
        if let t = track {
            showToast("Subtitles: \(t.name)")
        } else {
            showToast("Subtitles Off")
        }
    }
    
    public func setSubtitleDelay(_ delay: TimeInterval) {
        self.subtitleDelay = delay
        let ms = Int(delay * 1000)
        showToast("Subtitle Sync: \(ms > 0 ? "+\(ms)" : "\(ms)") ms")
    }
    
    private func updateSubtitleCue(at time: TimeInterval) {
        guard let track = selectedSubtitleTrack, !track.cues.isEmpty else {
            activeSubtitleCue = nil
            return
        }
        activeSubtitleCue = SubtitleParser.shared.cue(in: track.cues, at: time, delay: subtitleDelay)
    }
    
    // MARK: - Audio Tracks Discovery
    
    private func discoverAudioTracks(asset: AVAsset) {
        Task { [weak self] in
            guard let self = self else { return }
            var tracks: [MediaAudioTrack] = []
            if let mediaGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
                for option in mediaGroup.options {
                    let title = option.displayName
                    let lang = option.locale?.localizedString(forLanguageCode: option.locale?.language.languageCode?.identifier ?? "")
                    tracks.append(MediaAudioTrack(id: option.displayName, name: title, language: lang))
                }
            }
            self.availableAudioTracks = tracks
            self.selectedAudioTrack = tracks.first
        }
    }
    
    public func selectAudioTrack(_ track: MediaAudioTrack) {
        guard let item = player.currentItem else { return }
        self.selectedAudioTrack = track
        
        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                if let option = group.options.first(where: { $0.displayName == track.name }) {
                    item.select(option, in: group)
                    await MainActor.run {
                        self.showToast("Audio Track: \(track.name)")
                    }
                }
            }
        }
    }
    
    public func setAudioDelay(_ delay: TimeInterval) {
        self.audioDelay = delay
        let ms = Int(delay * 1000)
        showToast("Audio Sync: \(ms > 0 ? "+\(ms)" : "\(ms)") ms")
    }
    
    // MARK: - Video Equalizer Controls
    
    public func resetVideoFilters() {
        brightness = 0.0
        contrast = 1.0
        saturation = 1.0
        hueRotation = 0.0
        showToast("Video Filters Reset")
    }
    
    // MARK: - Playlist Navigation
    
    public func nextTrack() {
        guard !playlist.isEmpty else { return }
        if currentPlaylistIndex + 1 < playlist.count {
            currentPlaylistIndex += 1
            loadCurrentPlaylistItem()
        } else if isRepeatAll {
            currentPlaylistIndex = 0
            loadCurrentPlaylistItem()
        }
    }
    
    public func previousTrack() {
        guard !playlist.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
        } else if currentPlaylistIndex > 0 {
            currentPlaylistIndex -= 1
            loadCurrentPlaylistItem()
        }
    }
    
    private func handleItemDidFinishPlaying() {
        if isRepeatOne {
            seek(to: 0)
            play()
        } else if currentPlaylistIndex + 1 < playlist.count {
            nextTrack()
        } else if isRepeatAll {
            currentPlaylistIndex = 0
            loadCurrentPlaylistItem()
        } else {
            isPlaying = false
        }
    }
    
    // MARK: - Periodic Time Tick
    
    private func onTimeUpdate(time: CMTime) {
        let sec = CMTimeGetSeconds(time)
        guard sec.isFinite && !sec.isNaN else { return }
        
        currentTime = sec
        
        // Handle A-B Repeat Loop
        if let a = abLoopPointA, let b = abLoopPointB, b > a {
            if sec >= b {
                seek(to: a)
            }
        }
        
        // Update Subtitle
        updateSubtitleCue(at: sec)
        
        // Save playback position periodically
        if let url = currentVideoURL {
            savedPositions[url.absoluteString] = sec
        }
    }
    
    // MARK: - Recent Files Management
    
    private func loadSavedRecentFiles() {
        if let data = UserDefaults.standard.array(forKey: "SwitchRecentMediaFiles") as? [String] {
            self.recentFiles = data.compactMap { URL(string: $0) }
        }
    }
    
    private func addToRecentFiles(url: URL) {
        var list = recentFiles
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > 15 {
            list = Array(list.prefix(15))
        }
        self.recentFiles = list
        UserDefaults.standard.set(list.map { $0.absoluteString }, forKey: "SwitchRecentMediaFiles")
    }
    
    // MARK: - Set As Default Video Player
    
    @discardableResult
    public func setAsDefaultVideoPlayer() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.armank.switch"
        let videoUTIs = [
            "public.movie",
            "public.video",
            "public.audiovisual-content",
            "com.apple.quicktime-movie",
            "public.mpeg-4",
            "public.avi",
            "org.matroska.mkv",
            "com.microsoft.windows-media-wmv"
        ]
        
        var allOk = true
        for uti in videoUTIs {
            let res = LSSetDefaultRoleHandlerForContentType(uti as CFString, .viewer, bundleID as CFString)
            if res != noErr {
                allOk = false
            }
        }
        
        showToast(allOk ? "Switch set as default Mac video player!" : "Configured Switch for media files.")
        return allOk
    }
    
    // MARK: - Helper UI Formatting
    
    public func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
    
    public var statusSubtitle: String {
        if isPlaying {
            return "▶ \(videoTitle) (\(formatTime(currentTime)))"
        } else if currentVideoURL != nil {
            return "❚❚ \(videoTitle)"
        } else {
            return "VLC + IINA Player Ready"
        }
    }
    
    public func showToast(_ text: String) {
        self.statusToast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.statusToast == text {
                withAnimation {
                    self.statusToast = nil
                }
            }
        }
    }
}

