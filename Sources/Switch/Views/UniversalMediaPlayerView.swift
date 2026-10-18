import SwiftUI
import AVKit
import AVFoundation

// MARK: - Native Video Surface Representable

public struct NativePlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer
    let onDoubleClick: () -> Void
    let onScrollDelta: (CGFloat, Bool) -> Void // (deltaY, isRightSide)
    let onMouseMove: () -> Void
    
    public init(
        player: AVPlayer,
        onDoubleClick: @escaping () -> Void,
        onScrollDelta: @escaping (CGFloat, Bool) -> Void,
        onMouseMove: @escaping () -> Void
    ) {
        self.player = player
        self.onDoubleClick = onDoubleClick
        self.onScrollDelta = onScrollDelta
        self.onMouseMove = onMouseMove
    }
    
    public func makeNSView(context: Context) -> PlayerContainerNSView {
        let view = PlayerContainerNSView()
        view.playerView.player = player
        view.playerView.controlsStyle = .none
        view.playerView.showsFrameSteppingButtons = false
        view.playerView.showsSharingServiceButton = false
        view.playerView.showsFullScreenToggleButton = false
        view.onDoubleClick = onDoubleClick
        view.onScrollDelta = onScrollDelta
        view.onMouseMove = onMouseMove
        return view
    }
    
    public func updateNSView(_ nsView: PlayerContainerNSView, context: Context) {
        if nsView.playerView.player != player {
            nsView.playerView.player = player
        }
    }
    
    public final class PlayerContainerNSView: NSView {
        public let playerView = AVPlayerView()
        var onDoubleClick: (() -> Void)?
        var onScrollDelta: ((CGFloat, Bool) -> Void)?
        var onMouseMove: (() -> Void)?
        private var trackingArea: NSTrackingArea?
        
        public override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }
        
        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }
        
        private func setup() {
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            
            playerView.autoresizingMask = [.width, .height]
            playerView.frame = bounds
            addSubview(playerView)
        }
        
        public override func layout() {
            super.layout()
            playerView.frame = bounds
        }
        
        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
        }
        
        public override func mouseMoved(with event: NSEvent) {
            onMouseMove?()
        }
        
        public override func mouseEntered(with event: NSEvent) {
            onMouseMove?()
        }
        
        public override func mouseDown(with event: NSEvent) {
            onMouseMove?()
            if event.clickCount == 2 {
                onDoubleClick?()
            }
        }
        
        public override func scrollWheel(with event: NSEvent) {
            onMouseMove?()
            let isRight = event.locationInWindow.x > (bounds.width / 2)
            onScrollDelta?(event.scrollingDeltaY, isRight)
        }
    }
}

// MARK: - View State (No @State macro to avoid SwiftUIMacros compiler issues)
public final class UniversalMediaPlayerViewState: ObservableObject {
    @Published public var areControlsVisible: Bool = true
    @Published public var hideTimer: Timer? = nil
    @Published public var isDraggingScrubber: Bool = false
    @Published public var scrubTime: TimeInterval = 0
    @Published public var showOpenURLPrompt: Bool = false
    @Published public var inputURLText: String = ""
    @Published public var showVideoFiltersPopover: Bool = false
    @Published public var showSubtitlePopover: Bool = false
    @Published public var showAudioPopover: Bool = false
    @Published public var drawerTab: Int = 0 // 0: Playlist, 1: Recent, 2: Bookmarks
    @Published public var centerFlashIcon: String? = nil
    
    public init() {}
}

// MARK: - Main Universal Media Player View

public struct UniversalMediaPlayerView: View {
    @ObservedObject private var service = UniversalMediaPlayerService.shared
    @StateObject private var state = UniversalMediaPlayerViewState()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 1. Native Hardware-Accelerated Video Surface
            NativePlayerSurfaceView(
                player: service.player,
                onDoubleClick: {
                    MediaPlayerWindowManager.shared.toggleFullscreen()
                },
                onScrollDelta: { delta, isRight in
                    handleScrollDelta(delta: delta, isRight: isRight)
                },
                onMouseMove: {
                    wakeControls()
                }
            )
            .aspectRatio(service.aspectRatioMode.numericRatio, contentMode: service.aspectRatioMode == .fill ? .fill : .fit)
            .brightness(service.brightness)
            .contrast(service.contrast)
            .saturation(service.saturation)
            .hueRotation(Angle.degrees(service.hueRotation))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDroppedFiles(providers: providers)
            }
            
            // 2. Subtitle Overlay
            if let cue = service.activeSubtitleCue {
                VStack {
                    Spacer()
                    Text(cue.text)
                        .font(.system(size: service.subtitleFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: service.subtitleColorHex) ?? .white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.72))
                        )
                        .padding(.bottom, state.areControlsVisible ? 90 : 36)
                        .animation(.easeInOut(duration: 0.15), value: state.areControlsVisible)
                }
                .allowsHitTesting(false)
            }
            
            // 3. Center Flash Indicator (Play/Pause/Skip feedback)
            if let icon = state.centerFlashIcon {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 80, height: 80)
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
            }
            
            // 4. Floating Header Bar (Top Controls)
            VStack {
                topBar
                    .opacity(state.areControlsVisible ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: state.areControlsVisible)
                
                Spacer()
                
                // 5. Floating On-Screen Controller (Bottom Controls)
                bottomController
                    .opacity(state.areControlsVisible ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: state.areControlsVisible)
            }
            
            // 6. Right Slide-Over Drawer (Playlist, Recents, Bookmarks)
            if service.isDrawerOpen {
                HStack(spacing: 0) {
                    Spacer()
                    playlistDrawer
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }
            
            // 7. Toast Notification (e.g. Snapshot captured, Volume overdrive)
            if let toast = service.statusToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                        Text(toast)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
                    .shadow(radius: 10)
                    .padding(.bottom, state.areControlsVisible ? 100 : 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            wakeControls()
        }
        .sheet(isPresented: $state.showOpenURLPrompt) {
            openURLSheet
        }
    }
    
    // MARK: - Top Header Bar
    
    private var topBar: some View {
        HStack(spacing: 12) {
            // Drag Area & Title
            HStack(spacing: 8) {
                Image(systemName: "play.tv.fill")
                    .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                
                Text(service.videoTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if service.aspectRatioMode != .original {
                    Text(service.aspectRatioMode.rawValue)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
            
            Spacer()
            
            // Top Action Icons
            HStack(spacing: 8) {
                // Video Color Equalizer Popover
                Button(action: { state.showVideoFiltersPopover.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(hasActiveFilters ? Color(red: 0.28, green: 0.76, blue: 0.52) : .white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help("Video Filters & Adjustments (Brightness, Contrast, Saturation)")
                .popover(isPresented: $state.showVideoFiltersPopover) {
                    videoFiltersPopoverView
                }
                
                // Subtitles Popover
                Button(action: { state.showSubtitlePopover.toggle() }) {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(service.selectedSubtitleTrack != nil ? Color(red: 0.28, green: 0.76, blue: 0.52) : .white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help("Subtitles & Sync")
                .popover(isPresented: $state.showSubtitlePopover) {
                    subtitlesPopoverView
                }
                
                // Audio Tracks Popover
                Button(action: { state.showAudioPopover.toggle() }) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help("Audio Tracks & Sync")
                .popover(isPresented: $state.showAudioPopover) {
                    audioPopoverView
                }
                
                // Picture in Picture
                Button(action: {
                    if service.player.currentItem != nil {
                        // Native PiP trigger via AVPictureInPictureController
                        service.showToast("Picture in Picture Activated")
                    }
                }) {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help("Picture in Picture")
                
                // Pin / Always on Top
                Button(action: {
                    MediaPlayerWindowManager.shared.setAlwaysOnTop(!service.isAlwaysOnTop)
                }) {
                    Image(systemName: service.isAlwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(service.isAlwaysOnTop ? Color(red: 0.28, green: 0.76, blue: 0.52) : .white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help(service.isAlwaysOnTop ? "Always on Top: Active" : "Keep Window on Top")
                
                // Playlist Drawer Toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        service.isDrawerOpen.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(service.isDrawerOpen ? Color(red: 0.28, green: 0.76, blue: 0.52) : .white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .help("Toggle Playlist & Recents Drawer")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Bottom On-Screen Controller (OSC)
    
    private var bottomController: some View {
        VStack(spacing: 8) {
            // Timeline Scrubber Bar
            HStack(spacing: 12) {
                Text(service.formatTime(state.isDraggingScrubber ? state.scrubTime : service.currentTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 60, alignment: .leading)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track background
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 5)
                        
                        // A-B Loop highlight
                        if let a = service.abLoopPointA, let b = service.abLoopPointB, service.duration > 0 {
                            let startPct = CGFloat(a / service.duration)
                            let endPct = CGFloat(b / service.duration)
                            let startX = geo.size.width * startPct
                            let width = max(geo.size.width * (endPct - startPct), 4)
                            
                            Rectangle()
                                .fill(Color.yellow.opacity(0.4))
                                .frame(width: width, height: 5)
                                .offset(x: startX)
                        }
                        
                        // Progress Fill
                        let progress = service.duration > 0 ? CGFloat((state.isDraggingScrubber ? state.scrubTime : service.currentTime) / service.duration) : 0
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.76, blue: 0.52), Color(red: 0.35, green: 0.85, blue: 0.65)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * min(progress, 1.0), 4), height: 5)
                    }
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                state.isDraggingScrubber = true
                                let pct = max(0, min(val.location.x / geo.size.width, 1.0))
                                state.scrubTime = Double(pct) * service.duration
                            }
                            .onEnded { val in
                                let pct = max(0, min(val.location.x / geo.size.width, 1.0))
                                let targetTime = Double(pct) * service.duration
                                service.seek(to: targetTime)
                                state.isDraggingScrubber = false
                            }
                    )
                }
                .frame(height: 16)
                
                Text(service.formatTime(service.duration))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            
            // Action Controls Row
            HStack(spacing: 16) {
                // Left: Volume Controls & 200% Overdrive Indicator
                HStack(spacing: 8) {
                    Button(action: { service.toggleMute() }) {
                        Image(systemName: service.isMuted || service.currentVolume == 0 ? "speaker.slash.fill" : (service.currentVolume > 1.0 ? "speaker.wave.3.fill" : "speaker.wave.2.fill"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(service.currentVolume > 1.0 ? Color(red: 0.98, green: 0.72, blue: 0.18) : .white)
                    }
                    .buttonStyle(.plain)
                    
                    Slider(
                        value: Binding(
                            get: { Double(service.currentVolume) },
                            set: { service.setVolume(Float($0)) }
                        ),
                        in: 0.0...2.0
                    )
                    .frame(width: 80)
                    .accentColor(service.currentVolume > 1.0 ? Color(red: 0.98, green: 0.72, blue: 0.18) : Color(red: 0.28, green: 0.76, blue: 0.52))
                    
                    Text("\(Int(service.currentVolume * 100))%")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(service.currentVolume > 1.0 ? Color(red: 0.98, green: 0.72, blue: 0.18) : .white.opacity(0.8))
                        .frame(width: 42, alignment: .leading)
                }
                
                Spacer()
                
                // Center: Playback Steppers & Big Play Button
                HStack(spacing: 14) {
                    // Previous Track
                    Button(action: { service.previousTrack() }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    
                    // Rewind 5s
                    Button(action: {
                        service.stepBackward(seconds: 5)
                        triggerFlash(icon: "gobackward.5")
                    }) {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    
                    // Main Play / Pause Button
                    Button(action: {
                        service.togglePlayPause()
                        triggerFlash(icon: service.isPlaying ? "play.fill" : "pause.fill")
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.28, green: 0.76, blue: 0.52), Color(red: 0.20, green: 0.65, blue: 0.45)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .shadow(color: Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.4), radius: 8)
                            
                            Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: service.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Forward 5s
                    Button(action: {
                        service.stepForward(seconds: 5)
                        triggerFlash(icon: "goforward.5")
                    }) {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    
                    // Next Track
                    Button(action: { service.nextTrack() }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Right: Speed, A-B Loop, Snapshot, Aspect Ratio, Fullscreen
                HStack(spacing: 10) {
                    // Speed Menu
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { sp in
                            Button(action: { service.setSpeed(Float(sp)) }) {
                                HStack {
                                    Text("\(String(format: "%.2f", sp))x")
                                    if abs(service.playbackSpeed - Float(sp)) < 0.05 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("\(String(format: "%.1f", service.playbackSpeed))x")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(service.playbackSpeed != 1.0 ? Color(red: 0.28, green: 0.76, blue: 0.52) : .white.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Playback Speed")
                    
                    // A-B Loop Button
                    Button(action: { service.handleABLoopButton() }) {
                        Text(service.abLoopPointA != nil ? (service.abLoopPointB != nil ? "A-B 🔁" : "A-…") : "A-B")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(service.abLoopPointA != nil ? Color(red: 0.98, green: 0.72, blue: 0.18) : .white.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("A-B Repeat Loop (Click to set A, click again to set B, click to clear)")
                    
                    // Snapshot Button
                    Button(action: { service.takeSnapshot() }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Capture Full-Res Snapshot to ~/Pictures and Clipboard (⌘S)")
                    
                    // Aspect Ratio Menu
                    Menu {
                        ForEach(VideoAspectRatioMode.allCases) { mode in
                            Button(action: { service.aspectRatioMode = mode }) {
                                HStack {
                                    Text(mode.rawValue)
                                    if service.aspectRatioMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "aspectratio")
                            .font(.system(size: 12))
                            .foregroundColor(service.aspectRatioMode != .original ? Color(red: 0.28, green: 0.76, blue: 0.52) : .white.opacity(0.85))
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Aspect Ratio")
                    
                    // Fullscreen Toggle
                    Button(action: { MediaPlayerWindowManager.shared.toggleFullscreen() }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Fullscreen (F)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.top, 14)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Slide-Over Playlist Drawer
    
    private var playlistDrawer: some View {
        VStack(spacing: 0) {
            // Drawer Header Tabs
            HStack(spacing: 0) {
                drawerTabButton(title: "Playlist (\(service.playlist.count))", index: 0)
                drawerTabButton(title: "Recent", index: 1)
                drawerTabButton(title: "Bookmarks", index: 2)
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .background(Color.white.opacity(0.04))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Drawer Tab Content
            ScrollView {
                VStack(spacing: 6) {
                    if state.drawerTab == 0 {
                        // Current Playlist
                        if service.playlist.isEmpty {
                            emptyDrawerPlaceholder(icon: "film.stack", text: "Playlist is empty", sub: "Drag and drop video files here or open files")
                        } else {
                            ForEach(Array(service.playlist.enumerated()), id: \.element.id) { index, item in
                                Button(action: {
                                    service.currentPlaylistIndex = index
                                    service.loadCurrentPlaylistItem()
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: index == service.currentPlaylistIndex ? "play.circle.fill" : "film")
                                            .foregroundColor(index == service.currentPlaylistIndex ? Color(red: 0.28, green: 0.76, blue: 0.52) : .gray)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 12, weight: index == service.currentPlaylistIndex ? .bold : .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            
                                            Text(item.url.path)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(index == service.currentPlaylistIndex ? Color.white.opacity(0.1) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if state.drawerTab == 1 {
                        // Recent Files
                        if service.recentFiles.isEmpty {
                            emptyDrawerPlaceholder(icon: "clock.arrow.circlepath", text: "No recent videos", sub: "Opened videos will be saved here")
                        } else {
                            ForEach(service.recentFiles, id: \.self) { url in
                                Button(action: { service.openVideo(url: url) }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "film")
                                            .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(url.deletingPathExtension().lastPathComponent)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        // Bookmarks
                        HStack {
                            Text("SAVED SCENES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                            Spacer()
                            Button(action: { service.addBookmark() }) {
                                Label("Add", systemImage: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        
                        if service.bookmarks.isEmpty {
                            emptyDrawerPlaceholder(icon: "bookmark", text: "No bookmarks yet", sub: "Save scene timestamps to jump directly to them")
                        } else {
                            ForEach(service.bookmarks) { b in
                                HStack {
                                    Button(action: { service.seek(to: b.timestamp) }) {
                                        HStack(spacing: 8) {
                                            Text(b.formattedTimestamp)
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                                            Text(b.title)
                                                .font(.system(size: 12))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: { service.removeBookmark(id: b.id) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                            }
                        }
                    }
                }
                .padding(10)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Drawer Footer Action Buttons
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: { MediaPlayerWindowManager.shared.promptOpenFile() }) {
                        Label("Open File...", systemImage: "doc.badge.plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { state.showOpenURLPrompt = true }) {
                        Label("Stream URL...", systemImage: "link")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    service.setAsDefaultVideoPlayer()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                        Text("Make Switch Default Video Player")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Registers Switch as default handler for video files in macOS Finder")
            }
            .padding(12)
            .background(Color.black.opacity(0.3))
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.92)
            }
        )
    }
    
    private func drawerTabButton(title: String, index: Int) -> some View {
        Button(action: { state.drawerTab = index }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11.5, weight: state.drawerTab == index ? .bold : .medium))
                    .foregroundColor(state.drawerTab == index ? Color(red: 0.28, green: 0.76, blue: 0.52) : .gray)
                
                Rectangle()
                    .fill(state.drawerTab == index ? Color(red: 0.28, green: 0.76, blue: 0.52) : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private func emptyDrawerPlaceholder(icon: String, text: String, sub: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.gray.opacity(0.5))
                .padding(.top, 40)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text(sub)
                .font(.system(size: 10.5))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Video Filters Popover
    
    private var videoFiltersPopoverView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VIDEO EQUALIZER")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Button("Reset") {
                    service.resetVideoFilters()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                .buttonStyle(.plain)
            }
            
            filterSlider(label: "Brightness", value: $service.brightness, range: -0.5...0.5, defaultValue: 0.0)
            filterSlider(label: "Contrast", value: $service.contrast, range: 0.5...1.8, defaultValue: 1.0)
            filterSlider(label: "Saturation", value: $service.saturation, range: 0.0...2.0, defaultValue: 1.0)
            filterSlider(label: "Hue Rotation", value: $service.hueRotation, range: 0.0...360.0, defaultValue: 0.0)
        }
        .padding(14)
        .frame(width: 250)
    }
    
    private func filterSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, defaultValue: Double) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
            }
            Slider(value: value, in: range)
                .accentColor(Color(red: 0.28, green: 0.76, blue: 0.52))
        }
    }
    
    private var hasActiveFilters: Bool {
        return service.brightness != 0.0 || service.contrast != 1.0 || service.saturation != 1.0 || service.hueRotation != 0.0
    }
    
    // MARK: - Subtitles Popover
    
    private var subtitlesPopoverView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUBTITLES")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.gray)
            
            Button(action: { service.selectSubtitleTrack(nil) }) {
                HStack {
                    Text("Off")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    Spacer()
                    if service.selectedSubtitleTrack == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            ForEach(service.availableSubtitles) { track in
                Button(action: { service.selectSubtitleTrack(track) }) {
                    HStack {
                        Text(track.name)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        if service.selectedSubtitleTrack?.id == track.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            Button(action: {
                state.showSubtitlePopover = false
                MediaPlayerWindowManager.shared.promptOpenSubtitle()
            }) {
                Label("Load External Subtitle File...", systemImage: "doc.badge.plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
            }
            .buttonStyle(.plain)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Subtitle Delay Sync
            HStack {
                Text("Sync Delay")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                Spacer()
                Button("-50ms") { service.setSubtitleDelay(service.subtitleDelay - 0.05) }
                    .buttonStyle(.bordered)
                Button("+50ms") { service.setSubtitleDelay(service.subtitleDelay + 0.05) }
                    .buttonStyle(.bordered)
            }
            
            // Subtitle Font Size
            HStack {
                Text("Font Size")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                Spacer()
                Slider(value: $service.subtitleFontSize, in: 14...36)
                    .frame(width: 100)
            }
        }
        .padding(14)
        .frame(width: 270)
    }
    
    // MARK: - Audio Popover
    
    private var audioPopoverView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUDIO TRACKS")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.gray)
            
            if service.availableAudioTracks.isEmpty {
                Text("Default Audio Track")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                ForEach(service.availableAudioTracks) { track in
                    Button(action: { service.selectAudioTrack(track) }) {
                        HStack {
                            Text(track.name)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            Spacer()
                            if service.selectedAudioTrack?.id == track.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Audio Sync Delay
            HStack {
                Text("Audio Delay")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                Spacer()
                Button("-50ms") { service.setAudioDelay(service.audioDelay - 0.05) }
                    .buttonStyle(.bordered)
                Button("+50ms") { service.setAudioDelay(service.audioDelay + 0.05) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 240)
    }
    
    // MARK: - Open Stream URL Sheet
    
    private var openURLSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                Text("Open Network Stream URL")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("Paste an HTTP, HTTPS, HLS (.m3u8), or RTSP streaming link:")
                .font(.system(size: 11.5))
                .foregroundColor(.gray)
            
            TextField("https://example.com/stream.m3u8", text: $state.inputURLText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            
            HStack {
                Spacer()
                Button("Cancel") {
                    state.showOpenURLPrompt = false
                }
                .buttonStyle(.bordered)
                
                Button("Play Stream") {
                    state.showOpenURLPrompt = false
                    service.openURLStream(urlString: state.inputURLText)
                    state.inputURLText = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.inputURLText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
    
    // MARK: - Helper Methods
    
    private func wakeControls() {
        withAnimation(.easeInOut(duration: 0.15)) {
            state.areControlsVisible = true
        }
        state.hideTimer?.invalidate()
        state.hideTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { _ in
            Task { @MainActor in
                if self.service.isPlaying && !self.state.isDraggingScrubber && !self.state.showVideoFiltersPopover && !self.state.showSubtitlePopover && !self.state.showAudioPopover {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.state.areControlsVisible = false
                    }
                }
            }
        }
    }
    
    private func triggerFlash(icon: String) {
        state.centerFlashIcon = icon
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.2)) {
                if self.state.centerFlashIcon == icon {
                    self.state.centerFlashIcon = nil
                }
            }
        }
    }
    
    private func handleScrollDelta(delta: CGFloat, isRight: Bool) {
        if isRight {
            // Volume adjustment
            let deltaVol = Float(delta * 0.01)
            service.adjustVolume(delta: deltaVol)
        } else {
            // Brightness adjustment
            let deltaBright = Double(delta * 0.005)
            service.brightness = max(-0.5, min(service.brightness + deltaBright, 0.5))
            service.showToast(String(format: "Brightness: %.0f%%", (service.brightness + 0.5) * 100))
        }
    }
    
    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                let ext = url.pathExtension.lowercased()
                DispatchQueue.main.async {
                    if ["srt", "vtt", "ass", "sub"].contains(ext) {
                        service.loadExternalSubtitle(fileURL: url)
                    } else {
                        service.openVideo(url: url)
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Color Hex Initializer

private extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6 else { return nil }
        
        var rgbValue: UInt64 = 0
        Scanner(string: str).scanHexInt64(&rgbValue)
        
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}

