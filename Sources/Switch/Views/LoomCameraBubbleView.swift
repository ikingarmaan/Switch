import SwiftUI
import AVFoundation
import AppKit

final class LoomBubbleViewState: ObservableObject {
    @Published var isHovered: Bool = false
    @Published var audioPulse: Bool = false
    @Published var showEmojiBar: Bool = false
}

public struct LoomCameraBubbleView: View {
    @ObservedObject var service: LoomRecorderService
    @StateObject private var state = LoomBubbleViewState()
    
    public init(service: LoomRecorderService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        let size = service.isPresenterMode ? 360 : service.bubbleSize.rawValue
        
        ZStack {
            // Drag support anywhere in background
            WindowDraggableView()
                .frame(width: size, height: size)
            
            // 0. Pulsing Audio Waveform Ring (when recording with Mic)
            if service.isRecording && service.isMicEnabled {
                LoomBubbleMaskShape(shape: service.bubbleShape)
                    .stroke(service.ringColor.color.opacity(0.35), lineWidth: 8)
                    .scaleEffect(state.audioPulse ? 1.08 : 1.02)
                    .opacity(state.audioPulse ? 0.8 : 0.2)
                    .animation(
                        Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: state.audioPulse
                    )
                    .onAppear {
                        state.audioPulse = true
                    }
            }
            
            // 1. Camera Feed / Avatar Placeholder
            Group {
                if service.isCameraVisible, let cameraSession = service.getCameraSession() {
                    LoomCameraPreviewRepresentable(
                        session: cameraSession,
                        isMirrored: service.isMirrored
                    )
                    .modifier(LoomCameraFilterModifier(filter: service.cameraFilter))
                } else {
                    // Avatar / Privacy mode
                    avatarFallbackView(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(LoomBubbleMaskShape(shape: service.bubbleShape))
            .allowsHitTesting(false)
            
            // 2. Glowing Border Ring
            bubbleBorderView(size: size)
                .frame(width: size, height: size)
                .allowsHitTesting(false)
            
            // 3. Floating Reaction Emojis Particles
            ZStack {
                ForEach(service.reactions) { item in
                    LoomFloatingEmojiView(emoji: item.emoji, xOffset: item.xOffset)
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            
            // 4. Recording Duration Badge (when recording & not hovered)
            if service.isRecording && !state.isHovered {
                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text(service.formattedDuration)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
            
            // 5. Permanent Stable Draggable Surface (Never unmounted - 120Hz native drag!)
            WindowDraggableView()
                .frame(width: size, height: size)
                .clipShape(LoomBubbleMaskShape(shape: service.bubbleShape))
            
            // 6. Hover Controls Overlay (Smooth fade - Never destroyed during drag!)
            hoverControlsOverlay(size: size)
                .opacity(state.isHovered ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: state.isHovered)
                .allowsHitTesting(state.isHovered)
        }
        .frame(width: size, height: size)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                state.isHovered = hovering
            }
        }
    }
    
    // MARK: - Avatar Fallback View
    @ViewBuilder
    private func avatarFallbackView(size: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.20, blue: 0.32),
                    Color(red: 0.08, green: 0.10, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(service.ringColor.color.opacity(0.2))
                        .frame(width: size * 0.45, height: size * 0.45)
                    
                    Text("AK")
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                if !service.isCameraVisible {
                    Text("Camera Off")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    @ViewBuilder
    private func bubbleBorderView(size: CGFloat) -> some View {
        let radius = size * service.bubbleShape.cornerRadiusPercentage
        let ringColor = service.ringColor.color
        
        if service.bubbleShape == .circle {
            if service.isRecording {
                Circle()
                    .stroke(
                        service.isPaused ? Color.orange : ringColor,
                        lineWidth: 3.5
                    )
                    .shadow(
                        color: (service.isPaused ? Color.orange : ringColor).opacity(0.7),
                        radius: 8
                    )
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .shadow(color: Color.black.opacity(0.4), radius: 6)
            }
        } else {
            if service.isRecording {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        service.isPaused ? Color.orange : ringColor,
                        lineWidth: 3.5
                    )
                    .shadow(
                        color: (service.isPaused ? Color.orange : ringColor).opacity(0.7),
                        radius: 8
                    )
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .shadow(color: Color.black.opacity(0.4), radius: 6)
            }
        }
    }
    
    // MARK: - Hover Overlay
    @ViewBuilder
    private func hoverControlsOverlay(size: CGFloat) -> some View {
        ZStack {
            // 1. Draggable background surface
            WindowDraggableView()
                .clipShape(LoomBubbleMaskShape(shape: service.bubbleShape))
            
            // 2. Dark gradient overlay for readability (allowsHitTesting: false so clicks hit the drag surface)
            LoomBubbleMaskShape(shape: service.bubbleShape)
                .fill(Color.black.opacity(0.48))
                .allowsHitTesting(false)
            
            VStack(spacing: 5) {
                // Top: Dedicated Drag Grip Handle
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Drag")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.8))
                )
                .overlay(
                    WindowDraggableView()
                        .clipShape(Capsule())
                )
                .padding(.top, 4)
                
                // Top Action Toolbar
                HStack(spacing: 8) {
                    // 1. Presenter / Expanded Mode Toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            service.togglePresenterMode()
                        }
                    }) {
                        Image(systemName: service.isPresenterMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(service.isPresenterMode ? "Exit Presenter Mode" : "Expand to Presenter Mode (360px)")
                    
                    // 2. Camera Visual Filter Menu
                    Menu {
                        ForEach(LoomCameraFilter.allCases) { filter in
                            Button(action: {
                                service.cameraFilter = filter
                            }) {
                                HStack {
                                    Text(filter.rawValue)
                                    if service.cameraFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Camera Visual Filters")
                    
                    // 3. Ring Color Menu
                    Menu {
                        ForEach(LoomRingColor.allCases) { color in
                            Button(action: {
                                service.ringColor = color
                            }) {
                                HStack {
                                    Text(color.rawValue)
                                    if service.ringColor == color {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(service.ringColor.color)
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Glow Ring Color Accent")
                    
                    // 4. Mirror / Flip Toggle
                    Button(action: {
                        service.isMirrored.toggle()
                    }) {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Flip / Mirror Camera")
                    
                    // 5. Shape Toggle (Circle / Rounded Square)
                    Button(action: {
                        service.bubbleShape = (service.bubbleShape == .circle) ? .roundedRect : .circle
                    }) {
                        Image(systemName: service.bubbleShape == .circle ? "square.fill" : "circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Shape (Circle / Squircle)")
                    
                    // 6. Camera On/Off Toggle
                    Button(action: {
                        service.isCameraVisible.toggle()
                    }) {
                        Image(systemName: service.isCameraVisible ? "video.fill" : "video.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(service.isCameraVisible ? .white : .red)
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Camera On / Avatar")
                    
                    // 7. Reaction Emojis Menu (Clean dropdown on click, center stays unobstructed)
                    Menu {
                        ForEach(["🎉 Party", "👍 Thumbs Up", "❤️ Heart", "🔥 Fire", "💡 Idea", "🚀 Rocket"], id: \.self) { item in
                            let emoji = String(item.prefix(2)).trimmingCharacters(in: .whitespaces)
                            Button(action: {
                                service.triggerReaction(emoji)
                            }) {
                                Text(item)
                            }
                        }
                    } label: {
                        Text("🎉")
                            .font(.system(size: 11))
                            .padding(6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Send Reaction Emoji")
                }
                .padding(.top, 4)
                
                Spacer()
                
                // Bottom: S / M / L Size Selector
                if !service.isPresenterMode {
                    HStack(spacing: 5) {
                        sizeButton(label: "S", size: .small)
                        sizeButton(label: "M", size: .medium)
                        sizeButton(label: "L", size: .large)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    .padding(.bottom, 8)
                } else {
                    Button(action: {
                        withAnimation(.spring()) {
                            service.isPresenterMode = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 10, weight: .bold))
                            Text("Exit Presenter")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func sizeButton(label: String, size: LoomBubbleSize) -> some View {
        Button(action: {
            service.bubbleSize = size
        }) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(service.bubbleSize == size ? Color.black : Color.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(service.bubbleSize == size ? Color.white : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Set Camera Bubble to \(size.label)")
    }
}

// MARK: - Animated Floating Reaction Particle View
struct LoomFloatingEmojiView: View {
    let emoji: String
    let xOffset: CGFloat
    @StateObject private var animState = LoomFloatingEmojiAnimState()
    
    var body: some View {
        Text(emoji)
            .font(.system(size: 28))
            .offset(x: xOffset, y: animState.yOffset)
            .scaleEffect(animState.scale)
            .opacity(animState.opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6)) {
                    animState.yOffset = -120
                    animState.scale = 1.3
                    animState.opacity = 0.0
                }
            }
    }
}

final class LoomFloatingEmojiAnimState: ObservableObject {
    @Published var yOffset: CGFloat = 20
    @Published var scale: CGFloat = 0.4
    @Published var opacity: Double = 1.0
}

// MARK: - Filter ViewModifier
struct LoomCameraFilterModifier: ViewModifier {
    let filter: LoomCameraFilter
    
    func body(content: Content) -> some View {
        switch filter {
        case .natural:
            content
        case .studioWarm:
            content
                .colorMultiply(Color(red: 1.05, green: 0.98, blue: 0.91))
                .contrast(1.06)
        case .vibrant:
            content
                .saturation(1.35)
                .contrast(1.10)
        case .noir:
            content
                .saturation(0.0)
                .contrast(1.22)
        case .coolCyber:
            content
                .colorMultiply(Color(red: 0.90, green: 0.98, blue: 1.08))
                .saturation(1.2)
        }
    }
}

// MARK: - Bubble Mask Shape
public struct LoomBubbleMaskShape: Shape {
    public let shape: LoomBubbleShape
    
    public init(shape: LoomBubbleShape) {
        self.shape = shape
    }
    
    public func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            return Circle().path(in: rect)
        case .roundedRect:
            let radius = rect.width * shape.cornerRadiusPercentage
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
    }
}

// MARK: - Native Draggable NSView (Drag Anywhere!)
public struct WindowDraggableView: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> LoomWindowDragNSView {
        LoomWindowDragNSView()
    }
    
    public func updateNSView(_ nsView: LoomWindowDragNSView, context: Context) {}
}

public final class LoomWindowDragNSView: NSView {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
    
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - NSViewRepresentable for Camera Layer
public struct LoomCameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession?
    let isMirrored: Bool
    
    public func makeNSView(context: Context) -> LoomCameraPreviewNSView {
        let view = LoomCameraPreviewNSView()
        view.session = session
        view.isMirrored = isMirrored
        return view
    }
    
    public func updateNSView(_ nsView: LoomCameraPreviewNSView, context: Context) {
        nsView.session = session
        nsView.isMirrored = isMirrored
        nsView.updatePreview()
    }
}

public final class LoomCameraPreviewNSView: NSView {
    var session: AVCaptureSession? {
        didSet {
            updatePreview()
        }
    }
    
    var isMirrored: Bool = true {
        didSet {
            updateMirroring()
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
    
    func updatePreview() {
        guard let session = session else {
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
            return
        }
        
        if previewLayer == nil || previewLayer?.session != session {
            previewLayer?.removeFromSuperlayer()
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer?.addSublayer(layer)
            self.previewLayer = layer
        } else {
            previewLayer?.frame = bounds
        }
        updateMirroring()
    }
    
    func updateMirroring() {
        if let connection = previewLayer?.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}
