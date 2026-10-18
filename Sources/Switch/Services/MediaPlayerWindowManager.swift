import Cocoa
import SwiftUI
import AVFoundation

public final class MediaPlayerWindowManager: NSObject, NSWindowDelegate, @unchecked Sendable {
    public static let shared = MediaPlayerWindowManager()
    
    private var window: NSWindow?
    private var keyEventMonitor: Any?
    
    private override init() {
        super.init()
    }
    
    public func showWindow() {
        UniversalMediaPlayerService.shared.isWindowOpen = true
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let playerView = UniversalMediaPlayerView()
        let hostingController = NSHostingController(rootView: playerView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 920, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        newWindow.center()
        newWindow.title = "Switch Player"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.backgroundColor = .black
        newWindow.isMovableByWindowBackground = false
        newWindow.minSize = NSSize(width: 480, height: 320)
        newWindow.collectionBehavior = [.fullScreenPrimary]
        
        // Register for file Drag & Drop
        newWindow.registerForDraggedTypes([.fileURL])
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        setupKeyboardShortcuts()
    }
    
    public func closeWindow() {
        UniversalMediaPlayerService.shared.pause()
        UniversalMediaPlayerService.shared.isWindowOpen = false
        window?.orderOut(nil)
    }
    
    public var isWindowVisible: Bool {
        return window?.isVisible ?? false
    }
    
    @MainActor
    public func toggleWindow() {
        if isWindowVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }
    
    @MainActor
    public func adjustWindowToVideoSize(_ size: CGSize) {
        guard let win = window, size.width > 0, size.height > 0 else { return }
        
        // Don't auto-resize if already in fullscreen
        if win.styleMask.contains(.fullScreen) { return }
        
        let screen = win.screen?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1400, height: 900)
        let maxW = screen.width * 0.85
        let maxH = screen.height * 0.85
        
        var targetW = size.width
        var targetH = size.height
        
        // Scale down to fit screen bounds while strictly maintaining aspect ratio
        let widthScale = maxW / targetW
        let heightScale = maxH / targetH
        let scale = min(1.0, min(widthScale, heightScale))
        
        targetW = max(560, targetW * scale)
        targetH = max(340, targetH * scale)
        
        let currentFrame = win.frame
        let newX = currentFrame.midX - (targetW / 2)
        let newY = currentFrame.midY - (targetH / 2)
        let targetFrame = NSRect(x: newX, y: newY, width: targetW, height: targetH)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().setFrame(targetFrame, display: true)
        }
    }
    
    @MainActor
    public func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }
    
    @MainActor
    public func setAlwaysOnTop(_ onTop: Bool) {
        window?.level = onTop ? .floating : .normal
        UniversalMediaPlayerService.shared.isAlwaysOnTop = onTop
    }
    
    @MainActor
    public func promptOpenFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .movie,
            .video,
            .audio,
            .quickTimeMovie,
            .mpeg4Movie,
            .avi
        ]
        
        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { response in
            if response == .OK {
                UniversalMediaPlayerService.shared.openVideos(urls: panel.urls)
            }
        }
    }
    
    @MainActor
    public func promptOpenSubtitle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an SRT or WebVTT Subtitle File"
        
        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { response in
            if response == .OK, let url = panel.url {
                UniversalMediaPlayerService.shared.loadExternalSubtitle(fileURL: url)
            }
        }
    }
    
    // MARK: - Keyboard Event Monitoring
    
    private func setupKeyboardShortcuts() {
        guard keyEventMonitor == nil else { return }
        
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let win = self.window, win.isKeyWindow else { return event }
            
            // Check if user is typing into a TextField
            if let firstResp = win.firstResponder as? NSTextView, firstResp.isEditable {
                return event
            }
            
            let s = UniversalMediaPlayerService.shared
            
            switch event.keyCode {
            case 49: // Space
                s.togglePlayPause()
                return nil
            case 123: // Left Arrow
                if event.modifierFlags.contains(.command) {
                    s.stepBackward(seconds: 15)
                } else {
                    s.stepBackward(seconds: 5)
                }
                return nil
            case 124: // Right Arrow
                if event.modifierFlags.contains(.command) {
                    s.stepForward(seconds: 15)
                } else {
                    s.stepForward(seconds: 5)
                }
                return nil
            case 126: // Up Arrow
                s.adjustVolume(delta: 0.05)
                return nil
            case 125: // Down Arrow
                s.adjustVolume(delta: -0.05)
                return nil
            case 3: // 'F'
                DispatchQueue.main.async {
                    self.toggleFullscreen()
                }
                return nil
            case 46: // 'M'
                s.toggleMute()
                return nil
            case 1: // 'S'
                if event.modifierFlags.contains(.command) {
                    s.takeSnapshot()
                } else {
                    // Cycle subtitles
                    if let cur = s.selectedSubtitleTrack, let idx = s.availableSubtitles.firstIndex(of: cur), idx + 1 < s.availableSubtitles.count {
                        s.selectSubtitleTrack(s.availableSubtitles[idx + 1])
                    } else if !s.availableSubtitles.isEmpty && s.selectedSubtitleTrack == nil {
                        s.selectSubtitleTrack(s.availableSubtitles.first)
                    } else {
                        s.selectSubtitleTrack(nil)
                    }
                }
                return nil
            case 33: // '[' (Speed Down)
                s.adjustSpeed(delta: -0.1)
                return nil
            case 30: // ']' (Speed Up)
                s.adjustSpeed(delta: 0.1)
                return nil
            case 42: // '\' (Reset Speed)
                s.setSpeed(1.0)
                return nil
            case 37: // 'L' (A-B Loop)
                s.handleABLoopButton()
                return nil
            case 31: // 'O'
                if event.modifierFlags.contains(.command) {
                    DispatchQueue.main.async {
                        self.promptOpenFile()
                    }
                    return nil
                }
            default:
                break
            }
            
            return event
        }
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowWillClose(_ notification: Notification) {
        UniversalMediaPlayerService.shared.pause()
        UniversalMediaPlayerService.shared.isWindowOpen = false
        NotificationCenter.default.post(name: .mediaPlayerDidChange, object: nil)
    }
}

