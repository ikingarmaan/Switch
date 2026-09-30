import Foundation
import Cocoa
import AVFoundation
import SwiftUI
import Combine

public extension Notification.Name {
    static let loomRecorderDidChange = Notification.Name("SwitchLoomRecorderDidChange")
    static let loomRecorderTick = Notification.Name("SwitchLoomRecorderTick")
}

public enum LoomBubbleSize: CGFloat, CaseIterable, Identifiable, Codable, Sendable {
    case small = 140
    case medium = 200
    case large = 280
    
    public var id: CGFloat { rawValue }
    
    public var label: String {
        switch self {
        case .small: return "Small (140px)"
        case .medium: return "Medium (200px)"
        case .large: return "Large (280px)"
        }
    }
}

public enum LoomBubbleShape: String, CaseIterable, Identifiable, Codable, Sendable {
    case circle = "Circle"
    case roundedRect = "Rounded Square"
    
    public var id: String { rawValue }
    
    public var cornerRadiusPercentage: CGFloat {
        switch self {
        case .circle: return 0.5
        case .roundedRect: return 0.22
        }
    }
}

public enum LoomCameraFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case natural = "Natural"
    case studioWarm = "Studio Warm"
    case vibrant = "Vibrant"
    case noir = "B&W Film"
    case coolCyber = "Cyber Blue"
    
    public var id: String { rawValue }
}

public enum LoomRingColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case coral = "Loom Coral"
    case purple = "Electric Purple"
    case cyan = "Neon Cyan"
    case gold = "Sunset Gold"
    case green = "Emerald Green"
    case white = "Frosted White"
    
    public var id: String { rawValue }
    
    public var color: Color {
        switch self {
        case .coral: return Color(red: 1.0, green: 0.28, blue: 0.34)
        case .purple: return Color(red: 0.65, green: 0.35, blue: 0.98)
        case .cyan: return Color(red: 0.0, green: 0.85, blue: 0.98)
        case .gold: return Color(red: 1.0, green: 0.72, blue: 0.15)
        case .green: return Color(red: 0.25, green: 0.90, blue: 0.50)
        case .white: return Color.white
        }
    }
}

public struct LoomReactionItem: Identifiable, Sendable {
    public let id: UUID
    public let emoji: String
    public let xOffset: CGFloat
    public let delay: Double
    
    public init(id: UUID = UUID(), emoji: String, xOffset: CGFloat, delay: Double = 0) {
        self.id = id
        self.emoji = emoji
        self.xOffset = xOffset
        self.delay = delay
    }
}

public final class LoomRecorderService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = LoomRecorderService()
    
    // MARK: - Published State
    @Published public private(set) var isSessionActive: Bool = false
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var formattedDuration: String = "00:00"
    
    // Camera Bubble Configurations
    @Published public var bubbleSize: LoomBubbleSize = .medium {
        didSet {
            UserDefaults.standard.set(bubbleSize.rawValue, forKey: "switch.loomBubbleSize")
            updateCameraPanelFrame()
        }
    }
    
    @Published public var bubbleShape: LoomBubbleShape = .circle {
        didSet {
            UserDefaults.standard.set(bubbleShape.rawValue, forKey: "switch.loomBubbleShape")
        }
    }
    
    @Published public var isCameraVisible: Bool = true {
        didSet {
            if isCameraVisible {
                cameraPanel?.orderFrontRegardless()
            } else {
                cameraPanel?.orderOut(nil)
            }
        }
    }
    
    @Published public var isMicEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isMicEnabled, forKey: "switch.loomMicEnabled")
        }
    }
    
    @Published public var isMirrored: Bool = true
    
    // Visual Effects, Ring Color & Reactions
    @Published public var cameraFilter: LoomCameraFilter = .natural
    @Published public var ringColor: LoomRingColor = .coral
    @Published public var isPresenterMode: Bool = false {
        didSet {
            updateCameraPanelFrame()
        }
    }
    @Published public var reactions: [LoomReactionItem] = []
    
    public func triggerReaction(_ emoji: String) {
        let count = 4
        for i in 0..<count {
            let offset = CGFloat.random(in: -45...45)
            let delay = Double(i) * 0.12
            let item = LoomReactionItem(emoji: emoji, xOffset: offset, delay: delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reactions.append(item)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.0) { [weak self] in
                self?.reactions.removeAll(where: { $0.id == item.id })
            }
        }
        NSSound(named: "Pop")?.play()
    }
    
    public func togglePresenterMode() {
        isPresenterMode.toggle()
    }
    
    @Published public private(set) var countdownValue: Int = 0
    @Published public private(set) var isCountingDown: Bool = false
    @Published public var lastRecordingURL: URL? = nil
    @Published public var showReviewModal: Bool = false
    
    // MARK: - Private Capture Properties
    private var cameraSession: AVCaptureSession?
    private var recordSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var screenInput: AVCaptureScreenInput?
    private var micInput: AVCaptureDeviceInput?
    private var movieDelegate: LoomMovieDelegate?
    
    // Floating Panels
    private var cameraPanel: NSPanel?
    private var controlBarPanel: NSPanel?
    private var countdownPanel: NSPanel?
    private var reviewPanel: NSPanel?
    
    // Timers & Queue
    private var recordTimer: Timer?
    private var countdownTimer: Timer?
    private let captureQueue = DispatchQueue(label: "com.armank.switch.loomCaptureQueue")
    
    override private init() {
        super.init()
        
        // Restore saved settings
        if let savedSize = UserDefaults.standard.object(forKey: "switch.loomBubbleSize") as? CGFloat,
           let size = LoomBubbleSize(rawValue: savedSize) {
            self.bubbleSize = size
        }
        if let savedShape = UserDefaults.standard.string(forKey: "switch.loomBubbleShape"),
           let shape = LoomBubbleShape(rawValue: savedShape) {
            self.bubbleShape = shape
        }
        if UserDefaults.standard.object(forKey: "switch.loomMicEnabled") != nil {
            self.isMicEnabled = UserDefaults.standard.bool(forKey: "switch.loomMicEnabled")
        }
    }
    
    // MARK: - Public Controls
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            startSession()
        } else {
            stopSession()
        }
    }
    
    public func startSession() {
        guard !isSessionActive else { return }
        isSessionActive = true
        
        setupCameraSession()
        showFloatingUI()
        
        NotificationCenter.default.post(name: .loomRecorderDidChange, object: true)
    }
    
    public func stopSession() {
        guard isSessionActive else { return }
        
        if isRecording {
            stopRecording(discard: false)
        }
        
        isSessionActive = false
        stopCameraSession()
        hideFloatingUI()
        
        NotificationCenter.default.post(name: .loomRecorderDidChange, object: false)
    }
    
    // MARK: - Recording Actions
    
    public func triggerRecordingToggle() {
        if isRecording {
            stopRecording(discard: false)
        } else if !isCountingDown {
            startCountdownAndRecord()
        }
    }
    
    public func startCountdownAndRecord() {
        guard !isRecording && !isCountingDown else { return }
        
        isCountingDown = true
        countdownValue = 3
        showCountdownOverlay()
        
        NSSound(named: "Tink")?.play()
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.countdownValue -= 1
            if self.countdownValue > 0 {
                NSSound(named: "Tink")?.play()
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                self.isCountingDown = false
                self.hideCountdownOverlay()
                self.startActualRecording()
            }
        }
    }
    
    public func skipCountdownAndStart() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        hideCountdownOverlay()
        startActualRecording()
    }
    
    private func startActualRecording() {
        guard !isRecording else { return }
        
        let recordingsDir = recordingsFolderURL()
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileURL = recordingsDir.appendingPathComponent("Loom_Recording_\(timestamp).mov")
        
        setupRecordingSession(outputURL: fileURL)
        
        NSSound(named: "Blow")?.play()
        
        isRecording = true
        isPaused = false
        recordingDuration = 0
        formattedDuration = "00:00"
        
        recordTimer?.invalidate()
        recordTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            self.recordingDuration += 1
            let mins = Int(self.recordingDuration) / 60
            let secs = Int(self.recordingDuration) % 60
            self.formattedDuration = String(format: "%02d:%02d", mins, secs)
            NotificationCenter.default.post(name: .loomRecorderTick, object: self.formattedDuration)
        }
        
        NotificationCenter.default.post(name: .loomRecorderDidChange, object: true)
    }
    
    public func pauseRecording() {
        guard isRecording, !isPaused, let output = movieOutput else { return }
        output.pauseRecording()
        isPaused = true
    }
    
    public func resumeRecording() {
        guard isRecording, isPaused, let output = movieOutput else { return }
        output.resumeRecording()
        isPaused = false
    }
    
    public func restartRecording() {
        stopRecording(discard: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.startCountdownAndRecord()
        }
    }
    
    public func stopRecording(discard: Bool = false) {
        guard isRecording else { return }
        
        recordTimer?.invalidate()
        recordTimer = nil
        
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            if let output = self.movieOutput, output.isRecording {
                output.stopRecording()
            }
            if let session = self.recordSession, session.isRunning {
                session.stopRunning()
            }
        }
        
        isRecording = false
        isPaused = false
        
        NSSound(named: "Hero")?.play()
        
        if discard, let url = lastRecordingURL {
            try? FileManager.default.removeItem(at: url)
            lastRecordingURL = nil
        }
        
        NotificationCenter.default.post(name: .loomRecorderDidChange, object: isSessionActive)
    }
    
    // MARK: - Post-Recording Sharing Helpers
    
    public func copyLastRecordingToClipboard() {
        guard let url = lastRecordingURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        
        NSSound(named: "Pop")?.play()
    }
    
    public func revealLastRecordingInFinder() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    public func openLastRecordingInQuickTime() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    public func deleteLastRecording() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
        showReviewModal = false
        hideReviewModal()
    }
    
    public func recordingsFolderURL() -> URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return moviesDir.appendingPathComponent("Switch Recordings", isDirectory: true)
    }
    
    public func openRecordingsFolder() {
        let url = recordingsFolderURL()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Camera Capture Session
    
    private func setupCameraSession() {
        if cameraSession != nil { return }
        
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            print("No video device found for Loom camera bubble")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            self.cameraSession = session
            
            captureQueue.async {
                session.startRunning()
            }
        } catch {
            print("Failed to initialize video input: \(error)")
        }
    }
    
    private func stopCameraSession() {
        captureQueue.async { [weak self] in
            if let session = self?.cameraSession, session.isRunning {
                session.stopRunning()
            }
            self?.cameraSession = nil
        }
    }
    
    public func getCameraSession() -> AVCaptureSession? {
        return cameraSession
    }
    
    // MARK: - Screen Recording Setup
    
    private func setupRecordingSession(outputURL: URL) {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // 1. Screen Input
        guard let screenInput = AVCaptureScreenInput(displayID: CGMainDisplayID()) else {
            print("Failed to create AVCaptureScreenInput")
            return
        }
        screenInput.capturesCursor = true
        screenInput.capturesMouseClicks = true
        screenInput.minFrameDuration = CMTime(value: 1, timescale: 60)
        
        if session.canAddInput(screenInput) {
            session.addInput(screenInput)
            self.screenInput = screenInput
        }
        
        // 2. Microphone Input
        if isMicEnabled, let micDevice = AVCaptureDevice.default(for: .audio) {
            if let micInput = try? AVCaptureDeviceInput(device: micDevice) {
                if session.canAddInput(micInput) {
                    session.addInput(micInput)
                    self.micInput = micInput
                }
            }
        }
        
        // 3. Movie File Output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 1)
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            self.movieOutput = movieOutput
        }
        
        self.recordSession = session
        
        let delegate = LoomMovieDelegate()
        delegate.onFinish = { [weak self] finishedURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let url = finishedURL, error == nil {
                    self.lastRecordingURL = url
                    self.showReviewModal = true
                    self.presentReviewModal()
                } else if let error = error {
                    print("Recording error: \(error.localizedDescription)")
                }
            }
        }
        self.movieDelegate = delegate
        
        captureQueue.async {
            session.startRunning()
            movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)
        }
    }
    
    // MARK: - Floating Panels Lifecycle
    
    private func showFloatingUI() {
        setupCameraPanelIfNeeded()
        setupControlBarPanelIfNeeded()
        
        if isCameraVisible {
            cameraPanel?.orderFrontRegardless()
        }
        controlBarPanel?.orderFrontRegardless()
    }
    
    private func hideFloatingUI() {
        cameraPanel?.orderOut(nil)
        controlBarPanel?.orderOut(nil)
        countdownPanel?.orderOut(nil)
        reviewPanel?.orderOut(nil)
    }
    
    // MARK: - Camera Bubble Panel
    
    private func setupCameraPanelIfNeeded() {
        if cameraPanel != nil { return }
        
        guard NSScreen.main != nil else { return }
        let size = bubbleSize.rawValue
        
        // Default position: Bottom-Left (classic Loom placement)
        let x: CGFloat = 36
        let y: CGFloat = 80
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: LoomCameraBubbleView(service: self))
        panel.contentView = hostingView
        self.cameraPanel = panel
    }
    
    public func updateCameraPanelFrame() {
        guard let panel = cameraPanel else { return }
        let newSize: CGFloat = isPresenterMode ? 360 : bubbleSize.rawValue
        let currentFrame = panel.frame
        let newFrame = NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: newSize, height: newSize)
        panel.setFrame(newFrame, display: true, animate: true)
    }
    
    // MARK: - Floating Control Bar Panel
    
    private func setupControlBarPanelIfNeeded() {
        if controlBarPanel != nil { return }
        
        guard NSScreen.main != nil else { return }
        let width: CGFloat = 360
        let height: CGFloat = 56
        
        // Positioned next to the camera bubble or bottom center
        let x: CGFloat = 36
        let y: CGFloat = 20
        
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
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: LoomControlBarView(service: self))
        panel.contentView = hostingView
        self.controlBarPanel = panel
    }
    
    // MARK: - 3-2-1 Countdown Overlay
    
    private func showCountdownOverlay() {
        if countdownPanel == nil {
            guard let screen = NSScreen.main else { return }
            let size: CGFloat = 160
            let x = screen.frame.midX - (size / 2)
            let y = screen.frame.midY - (size / 2)
            
            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: size, height: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hosting = NSHostingView(rootView: LoomCountdownView(service: self))
            panel.contentView = hosting
            self.countdownPanel = panel
        }
        
        countdownPanel?.orderFrontRegardless()
    }
    
    private func hideCountdownOverlay() {
        countdownPanel?.orderOut(nil)
    }
    
    // MARK: - Post Recording Review Modal
    
    public func presentReviewModal() {
        if reviewPanel == nil {
            guard let screen = NSScreen.main else { return }
            let width: CGFloat = 520
            let height: CGFloat = 420
            let x = screen.frame.midX - (width / 2)
            let y = screen.frame.midY - (height / 2)
            
            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: width, height: height),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Loom Recording Ready"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces]
            
            let hosting = NSHostingView(rootView: LoomReviewModalView(service: self))
            panel.contentView = hosting
            self.reviewPanel = panel
        }
        
        reviewPanel?.center()
        reviewPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func hideReviewModal() {
        reviewPanel?.orderOut(nil)
    }
}

// MARK: - Movie Output Delegate

final class LoomMovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    var onFinish: ((URL?, Error?) -> Void)?
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        onFinish?(outputFileURL, error)
    }
}
