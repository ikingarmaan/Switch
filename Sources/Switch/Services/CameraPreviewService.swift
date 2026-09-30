import Cocoa
import AVFoundation
import SwiftUI

public extension Notification.Name {
    static let cameraPreviewDidChange = Notification.Name("SwitchCameraPreviewDidChange")
}

public final class CameraPreviewService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = CameraPreviewService()
    
    @Published public private(set) var isRunning: Bool = false
    @Published public var isMirrored: Bool = true
    @Published public var hasPermission: Bool = true
    
    private var captureSession: AVCaptureSession?
    private var previewPanel: NSPanel?
    private let sessionQueue = DispatchQueue(label: "com.armank.switch.cameraQueue")
    
    override private init() {
        super.init()
    }
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            start()
        } else {
            stop()
        }
    }
    
    public func start() {
        guard !isRunning else { return }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            self.hasPermission = true
            setupAndStartCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.hasPermission = true
                        self?.setupAndStartCapture()
                    } else {
                        self?.hasPermission = false
                        self?.showPanel()
                        NotificationCenter.default.post(name: .cameraPreviewDidChange, object: false)
                    }
                }
            }
        case .denied, .restricted:
            self.hasPermission = false
            showPanel()
            NotificationCenter.default.post(name: .cameraPreviewDidChange, object: false)
        @unknown default:
            break
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        
        sessionQueue.async { [weak self] in
            if let session = self?.captureSession, session.isRunning {
                session.stopRunning()
            }
        }
        
        hidePanel()
        NotificationCenter.default.post(name: .cameraPreviewDidChange, object: false)
    }
    
    private func setupAndStartCapture() {
        if captureSession == nil {
            let session = AVCaptureSession()
            session.sessionPreset = .high
            
            guard let device = AVCaptureDevice.default(for: .video) else {
                print("No video capture device available")
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                self.captureSession = session
            } catch {
                print("Error setting up camera input: \(error)")
                return
            }
        }
        
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession else { return }
            if !session.isRunning {
                session.startRunning()
            }
            DispatchQueue.main.async {
                self?.isRunning = true
                self?.showPanel()
                NotificationCenter.default.post(name: .cameraPreviewDidChange, object: true)
            }
        }
    }
    
    private func setupPanelIfNeeded() {
        if previewPanel != nil { return }
        
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let width: CGFloat = 320
        let height: CGFloat = 246
        
        // Attached directly to the menu bar at the physical camera location (top center)
        let x = screenFrame.midX - (width / 2)
        let y = visibleFrame.maxY - height - 2
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: CameraPreviewHUDView(service: self))
        panel.contentView = hostingView
        self.previewPanel = panel
    }
    
    private func showPanel() {
        setupPanelIfNeeded()
        
        // If window is at default or reopened, attach directly beneath the camera
        if let panel = previewPanel, let screen = NSScreen.main {
            let width = panel.frame.width
            let height = panel.frame.height
            // Only reposition to camera location if window is not already visible
            if !panel.isVisible {
                let x = screen.frame.midX - (width / 2)
                let y = screen.visibleFrame.maxY - height - 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        
        previewPanel?.orderFrontRegardless()
    }
    
    private func hidePanel() {
        previewPanel?.orderOut(nil)
    }
    
    func getCaptureSession() -> AVCaptureSession? {
        return captureSession
    }
}

// MARK: - Native Window Drag Handle

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        return WindowDragNSView()
    }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Camera Feed View Representable

private struct CameraVideoView: NSViewRepresentable {
    let session: AVCaptureSession?
    let isMirrored: Bool
    
    func makeNSView(context: Context) -> CameraVideoNSView {
        let view = CameraVideoNSView()
        view.setSession(session, isMirrored: isMirrored)
        return view
    }
    
    func updateNSView(_ nsView: CameraVideoNSView, context: Context) {
        nsView.setSession(session, isMirrored: isMirrored)
    }
}

private final class CameraVideoNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setSession(_ session: AVCaptureSession?, isMirrored: Bool) {
        guard let session = session else { return }
        
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            self.layer?.addSublayer(layer)
            self.previewLayer = layer
        } else {
            previewLayer?.session = session
        }
        
        if let connection = previewLayer?.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
        
        layoutLayer()
    }
    
    override func layout() {
        super.layout()
        layoutLayer()
    }
    
    private func layoutLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - SwiftUI HUD View

private struct CameraPreviewHUDView: View {
    @ObservedObject var service: CameraPreviewService
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Notch Anchor Pill (visual connector to the physical camera)
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
            .background(WindowDragHandle())
            
            // Header Bar (Draggable handle + controls)
            HStack(spacing: 8) {
                // Live indicator dot & Title
                HStack(spacing: 6) {
                    Circle()
                        .fill(service.isRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: (service.isRunning ? Color.green : Color.orange).opacity(0.8), radius: 3)
                    
                    Text("Camera Preview")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Flip / Mirror Button
                Button(action: {
                    service.isMirrored.toggle()
                }) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(service.isMirrored ? .accentColor : .white.opacity(0.7))
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(service.isMirrored ? "Mirror: ON" : "Mirror: OFF")
                
                // Close Button
                Button(action: {
                    service.stop()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Close Preview")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(WindowDragHandle())
            
            // Video / Content Box
            ZStack {
                if service.hasPermission {
                    if let session = service.getCaptureSession() {
                        CameraVideoView(session: session, isMirrored: service.isMirrored)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    } else {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Connecting camera...")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                } else {
                    // Permission Required View
                    VStack(spacing: 10) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                        
                        Text("Camera Permission Required")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Allow Switch to access your camera in System Settings.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text("Open Settings")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.88)
                WindowDragHandle()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
        )
    }
}
