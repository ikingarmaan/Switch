import Foundation
import Cocoa
import AVFoundation
import Combine
import SwiftUI

public extension Notification.Name {
    static let knockScreenshotDidChange = Notification.Name("SwitchKnockScreenshotDidChange")
    static let knockScreenshotStatusTick = Notification.Name("SwitchKnockScreenshotStatusTick")
}

public enum KnockSensitivity: String, CaseIterable, Identifiable, Codable, Sendable {
    case ultra = "Ultra (Gentle Tap)"
    case high = "High (Light Knocks)"
    case normal = "Normal (Balanced)"
    case low = "Low (Firm Knocks)"
    
    public var id: String { rawValue }
    
    public var threshold: Float {
        switch self {
        case .ultra: return 0.055
        case .high: return 0.085
        case .normal: return 0.13
        case .low: return 0.22
        }
    }
    
    public var quietThreshold: Float {
        switch self {
        case .ultra: return 0.038
        case .high: return 0.050
        case .normal: return 0.065
        case .low: return 0.090
        }
    }
    
    public var minInterval: TimeInterval {
        switch self {
        case .ultra: return 0.08
        case .high: return 0.09
        case .normal: return 0.11
        case .low: return 0.14
        }
    }
    
    public var maxInterval: TimeInterval {
        switch self {
        case .ultra: return 0.95
        case .high: return 0.90
        case .normal: return 0.80
        case .low: return 0.70
        }
    }
    
    public var crestFactorMin: Float {
        switch self {
        case .ultra: return 1.35
        case .high: return 1.50
        case .normal: return 1.70
        case .low: return 2.00
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .ultra: return "Ultra"
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        }
    }
}

public enum KnockScreenshotDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case desktop = "Desktop"
    case clipboard = "Clipboard"
    case both = "Desktop & Clipboard"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .desktop: return "display"
        case .clipboard: return "doc.on.clipboard"
        case .both: return "square.and.arrow.down.on.square"
        }
    }
}

private enum KnockDetectionState {
    case idle
    case knock1Active(t1: TimeInterval, peak1: Float)
    case knock1Quieted(t1: TimeInterval)
}

public final class KnockScreenshotService: ObservableObject, @unchecked Sendable {
    public static let shared = KnockScreenshotService()
    
    private let keySensitivity = "switch.knockScreenshot.sensitivity"
    private let keyDestination = "switch.knockScreenshot.destination"
    private let keyFlashScreen = "switch.knockScreenshot.flashScreen"
    private let keyPlaySound = "switch.knockScreenshot.playSound"
    
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var statusSubtitle: String = "2 Knocks"
    @Published public var sensitivity: KnockSensitivity = .high
    @Published public var destination: KnockScreenshotDestination = .desktop
    @Published public var flashScreen: Bool = true
    @Published public var playSound: Bool = true
    
    // Audio engine & processing
    private var audioEngine: AVAudioEngine?
    private let detectionQueue = DispatchQueue(label: "com.armank.switch.knockDetection", qos: .userInteractive)
    
    // State machine variables (accessed on detectionQueue)
    private var detectionState: KnockDetectionState = .idle
    private var lastTriggerTime: TimeInterval = 0
    private var ambientNoiseRMS: Float = 0.01
    private var sustainedLoudBuffers: Int = 0
    
    // UI timers & HUD
    private var timeoutTimer: Timer?
    private var toastPanel: NSPanel?
    private var toastDismissWorkItem: DispatchWorkItem?
    
    private init() {
        loadPreferences()
        
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isListening else { return }
            self.restartEngine()
        }
    }
    
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        if let savedSens = defaults.string(forKey: keySensitivity),
           let s = KnockSensitivity(rawValue: savedSens) {
            self.sensitivity = s
        } else {
            self.sensitivity = .high
        }
        
        if let savedDest = defaults.string(forKey: keyDestination),
           let d = KnockScreenshotDestination(rawValue: savedDest) {
            self.destination = d
        }
        
        if defaults.object(forKey: keyFlashScreen) != nil {
            self.flashScreen = defaults.bool(forKey: keyFlashScreen)
        }
        
        if defaults.object(forKey: keyPlaySound) != nil {
            self.playSound = defaults.bool(forKey: keyPlaySound)
        }
    }
    
    // MARK: - Enable / Disable
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            startListening()
        } else {
            stopListening()
        }
    }
    
    public func toggle() {
        setEnabled(!isListening)
    }
    
    public func setSensitivity(_ newSensitivity: KnockSensitivity) {
        self.sensitivity = newSensitivity
        UserDefaults.standard.set(newSensitivity.rawValue, forKey: keySensitivity)
        objectWillChange.send()
    }
    
    public func setDestination(_ newDestination: KnockScreenshotDestination) {
        self.destination = newDestination
        UserDefaults.standard.set(newDestination.rawValue, forKey: keyDestination)
        objectWillChange.send()
    }
    
    public func setFlashScreen(_ enable: Bool) {
        self.flashScreen = enable
        UserDefaults.standard.set(enable, forKey: keyFlashScreen)
        objectWillChange.send()
    }
    
    public func setPlaySound(_ enable: Bool) {
        self.playSound = enable
        UserDefaults.standard.set(enable, forKey: keyPlaySound)
        objectWillChange.send()
    }
    
    // MARK: - Engine Lifecycle
    
    public func startListening() {
        guard !isListening else { return }
        
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authStatus {
        case .authorized:
            startAudioEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startAudioEngine()
                    } else {
                        self?.isListening = false
                        self?.statusSubtitle = "Mic Access Required"
                        self?.showMicrophonePermissionAlert()
                        NotificationCenter.default.post(name: .knockScreenshotDidChange, object: false)
                    }
                }
            }
        case .denied, .restricted:
            self.isListening = false
            self.statusSubtitle = "Mic Access Denied"
            showMicrophonePermissionAlert()
            NotificationCenter.default.post(name: .knockScreenshotDidChange, object: false)
        @unknown default:
            break
        }
    }
    
    private func startAudioEngine() {
        stopAudioEngine()
        
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            self.isListening = false
            self.statusSubtitle = "Audio Device Unavailable"
            NotificationCenter.default.post(name: .knockScreenshotDidChange, object: false)
            return
        }
        
        // Use 512-frame buffer (~11.6ms at 44.1kHz) for fast transient response & decay resolution
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            self?.processIncomingBuffer(buffer)
        }
        
        do {
            try engine.start()
            self.audioEngine = engine
            self.isListening = true
            self.statusSubtitle = "Listening · Double Knock"
            NotificationCenter.default.post(name: .knockScreenshotDidChange, object: true)
        } catch {
            print("Failed to start KnockScreenshot audio engine: \(error)")
            self.isListening = false
            self.statusSubtitle = "Engine Failed"
            NotificationCenter.default.post(name: .knockScreenshotDidChange, object: false)
        }
    }
    
    public func stopListening() {
        stopAudioEngine()
        self.isListening = false
        self.statusSubtitle = "2 Knocks"
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        detectionState = .idle
        NotificationCenter.default.post(name: .knockScreenshotDidChange, object: false)
    }
    
    private func stopAudioEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
        }
    }
    
    private func restartEngine() {
        stopAudioEngine()
        if isListening {
            startAudioEngine()
        }
    }
    
    // MARK: - Audio Transient Analysis & State Machine
    
    private func processIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        var peak: Float = 0.0
        var sumSquares: Float = 0.0
        
        for ch in 0..<channelCount {
            let data = channelData[ch]
            for i in 0..<frameCount {
                let sample = abs(data[i])
                if sample > peak { peak = sample }
                sumSquares += sample * sample
            }
        }
        
        let totalSamples = Float(frameCount * max(1, channelCount))
        let rms = sqrt(sumSquares / totalSamples)
        
        detectionQueue.async { [weak self] in
            self?.evaluateAudioTransient(peak: peak, rms: rms)
        }
    }
    
    private func evaluateAudioTransient(peak: Float, rms: Float) {
        let now = ProcessInfo.processInfo.systemUptime
        
        // Prevent re-triggering during cooldown (1.5 seconds)
        if now - lastTriggerTime < 1.5 {
            detectionState = .idle
            return
        }
        
        // Continuous speech / music / background noise rejection:
        // Voice or music has sustained high RMS over multiple consecutive buffers.
        // A mechanical knock is an impulse lasting only ~5-25ms.
        if rms > 0.12 {
            sustainedLoudBuffers += 1
        } else {
            sustainedLoudBuffers = max(0, sustainedLoudBuffers - 1)
        }
        
        if sustainedLoudBuffers >= 4 {
            // Sustained noise/speech, cancel any open knock sequence
            if case .idle = detectionState { } else {
                detectionState = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.resetToListening()
                }
            }
            return
        }
        
        // Track ambient noise floor when quiet
        if peak < 0.05 {
            ambientNoiseRMS = 0.95 * ambientNoiseRMS + 0.05 * rms
        }
        
        let sens = sensitivity
        let thresh = sens.threshold
        let quietThresh = sens.quietThreshold
        let minCrest = sens.crestFactorMin
        let crestFactor = peak / max(rms, 0.0001)
        
        // Criteria for an authentic mechanical chassis knock impulse:
        // 1. Peak >= Sensitivity threshold
        // 2. High crest factor (steep spike relative to buffer RMS)
        // 3. RMS is not elevated (rejects microphone clipping/shouting)
        // 4. Stands clearly above ambient room noise floor
        let isTransient = (crestFactor >= minCrest) && (rms < peak * 0.75)
        let minAboveAmbient: Float = min(0.04, thresh * 0.75)
        let isAboveAmbient = peak >= max(minAboveAmbient, ambientNoiseRMS * 1.6)
        let isKnockImpact = (peak >= thresh) && isTransient && isAboveAmbient
        
        switch detectionState {
        case .idle:
            if isKnockImpact {
                detectionState = .knock1Active(t1: now, peak1: peak)
                DispatchQueue.main.async { [weak self] in
                    self?.onFirstKnockDetected()
                }
            }
            
        case .knock1Active(let t1, let peak1):
            let elapsed = now - t1
            if elapsed > sens.maxInterval {
                // First knock timed out without quiet + second knock
                detectionState = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.resetToListening()
                }
            } else if peak < quietThresh || peak < peak1 * 0.52 {
                // Signal dropped into quiet valley! The first knock's vibration has settled.
                detectionState = .knock1Quieted(t1: t1)
            }
            
        case .knock1Quieted(let t1):
            let elapsed = now - t1
            if elapsed > sens.maxInterval {
                // Timed out: user only knocked once
                detectionState = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.resetToListening()
                }
            } else if elapsed >= sens.minInterval && isKnockImpact {
                // GENUINE SECOND KNOCK CONFIRMED!
                detectionState = .idle
                lastTriggerTime = now
                DispatchQueue.main.async { [weak self] in
                    self?.onDoubleKnockDetected()
                }
            }
        }
    }
    
    // MARK: - Detection Feedback & Actions
    
    private func onFirstKnockDetected() {
        statusSubtitle = "Knock 1..."
        NotificationCenter.default.post(name: .knockScreenshotStatusTick, object: "Knock 1...")
        
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: sensitivity.maxInterval + 0.1, repeats: false) { [weak self] _ in
            guard let self = self, self.isListening else { return }
            self.resetToListening()
        }
    }
    
    private func resetToListening() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        if isListening {
            statusSubtitle = "Listening · Double Knock"
            NotificationCenter.default.post(name: .knockScreenshotStatusTick, object: statusSubtitle)
        }
    }
    
    private func onDoubleKnockDetected() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        takeScreenshot(isManual: false)
    }
    
    // MARK: - Screenshot Capture Execution
    
    public func takeScreenshotNow() {
        takeScreenshot(isManual: true)
    }
    
    public func takeScreenshot(isManual: Bool = false) {
        statusSubtitle = "Capturing..."
        NotificationCenter.default.post(name: .knockScreenshotStatusTick, object: "Capturing...")
        
        let currentDest = destination
        let shouldFlash = flashScreen
        let shouldSound = playSound
        
        Task.detached(priority: .userInitiated) { [weak self] in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let dateStr = formatter.string(from: Date())
            let filename = "Screenshot \(dateStr).png"
            
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
            let fileURL = desktopURL.appendingPathComponent(filename)
            
            // 1. CAPTURE THE SCREEN FIRST!
            // This guarantees the screenshot captures the screen completely untouched and 100% crystal clear.
            let (didSucceed, finalURL): (Bool, URL?) = {
                switch currentDest {
                case .desktop:
                    _ = Shell.run("/usr/sbin/screencapture -x \"\(fileURL.path)\" 2>&1")
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        return (true, fileURL)
                    }
                    return (false, nil)
                    
                case .clipboard:
                    _ = Shell.run("/usr/sbin/screencapture -c 2>&1")
                    return (true, nil)
                    
                case .both:
                    _ = Shell.run("/usr/sbin/screencapture -x \"\(fileURL.path)\" 2>&1")
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        if let image = NSImage(contentsOf: fileURL) {
                            DispatchQueue.main.async {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.writeObjects([image])
                            }
                        }
                        return (true, fileURL)
                    }
                    return (false, nil)
                }
            }()
            
            // 2. NOW THAT SCREENSHOT IS SAFELY ON DISK, PROVIDE TACTILE FEEDBACK!
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // Show gentle visual screen flash (invisible to screen recordings via sharingType = .none)
                if shouldFlash {
                    ScreenFlashOverlay.flash()
                }
                
                // Play camera shutter sound
                if shouldSound {
                    self.playShutterSound()
                }
                
                if didSucceed {
                    self.statusSubtitle = "Captured!"
                    self.showCaptureHUD(destination: currentDest, fileURL: finalURL)
                } else {
                    self.statusSubtitle = "Capture Failed"
                }
                NotificationCenter.default.post(name: .knockScreenshotStatusTick, object: self.statusSubtitle)
                
                // Return to listening state after brief confirmation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                    guard let self = self else { return }
                    if self.isListening {
                        self.statusSubtitle = "Listening · Double Knock"
                    } else {
                        self.statusSubtitle = "2 Knocks"
                    }
                    NotificationCenter.default.post(name: .knockScreenshotStatusTick, object: self.statusSubtitle)
                }
            }
        }
    }
    
    private func playShutterSound() {
        let soundPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if let sound = NSSound(contentsOfFile: soundPath, byReference: true) {
            sound.play()
        } else {
            NSSound(named: "Screen Capture")?.play()
        }
    }
    
    // MARK: - Capture Toast HUD
    
    private func showCaptureHUD(destination: KnockScreenshotDestination, fileURL: URL?) {
        toastDismissWorkItem?.cancel()
        
        let title: String
        let detail: String
        
        switch destination {
        case .desktop:
            title = "Screenshot Saved"
            detail = fileURL?.lastPathComponent ?? "Desktop"
        case .clipboard:
            title = "Screenshot Copied"
            detail = "Copied to Clipboard"
        case .both:
            title = "Screenshot Saved & Copied"
            detail = fileURL?.lastPathComponent ?? "Desktop & Clipboard"
        }
        
        if toastPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.sharingType = .none // Exclude from any screen captures
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            self.toastPanel = panel
        }
        
        guard let panel = toastPanel else { return }
        
        panel.contentView = NSHostingView(
            rootView: KnockCaptureToastView(
                title: title,
                detail: detail,
                fileURL: fileURL,
                onTap: { [weak self] in
                    if let url = fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    self?.toastPanel?.orderOut(nil)
                }
            )
        )
        
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 160
            let y = screen.visibleFrame.maxY - 75
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.orderFrontRegardless()
        
        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self?.toastPanel?.animator().alphaValue = 0.0
            }, completionHandler: {
                self?.toastPanel?.orderOut(nil)
                self?.toastPanel?.alphaValue = 1.0
            })
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }
    
    // MARK: - Helpers & Settings
    
    public func openScreenshotsFolder() {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        NSWorkspace.shared.open(desktopURL)
    }
    
    public func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "Switch requires microphone access to detect chassis double-knocks for instant screenshots.\n\nPlease enable Microphone access for Switch in System Settings > Privacy & Security > Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }
}

// MARK: - Screen Flash Overlay

public final class ScreenFlashOverlay {
    public static func flash() {
        DispatchQueue.main.async {
            var flashPanels: [NSPanel] = []
            
            for screen in NSScreen.screens {
                let panel = NSPanel(
                    contentRect: screen.frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.backgroundColor = .white
                panel.alphaValue = 0.38 // Soft natural flash
                panel.isOpaque = false
                panel.hasShadow = false
                panel.sharingType = .none // Excludes this window from any screen capture API
                panel.level = .screenSaver
                panel.ignoresMouseEvents = true
                panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
                panel.orderFrontRegardless()
                flashPanels.append(panel)
            }
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                for panel in flashPanels {
                    panel.animator().alphaValue = 0.0
                }
            }, completionHandler: {
                for panel in flashPanels {
                    panel.orderOut(nil)
                    panel.close()
                }
                flashPanels.removeAll()
            })
        }
    }
}

// MARK: - Knock Capture Toast View

public struct KnockCaptureToastView: View {
    let title: String
    let detail: String
    let fileURL: URL?
    let onTap: () -> Void
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Shutter Camera Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.20, green: 0.80, blue: 0.50), Color(red: 0.10, green: 0.65, blue: 0.40)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if fileURL != nil {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(4)
    }
}
