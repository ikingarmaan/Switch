import Foundation
import Cocoa
import AVFoundation
import Speech
import Combine
import SwiftUI
import ApplicationServices

public extension Notification.Name {
    static let wisprFlowStateDidChange = Notification.Name("SwitchWisprFlowStateDidChange")
    static let wisprFlowListeningDidChange = Notification.Name("SwitchWisprFlowListeningDidChange")
    static let wisprFlowDidTranscribe = Notification.Name("SwitchWisprFlowDidTranscribe")
    static let wisprFlowAudioLevelsTick = Notification.Name("SwitchWisprFlowAudioLevelsTick")
}

public enum WisprEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case geminiFlash = "geminiFlash"
    case groqWhisper = "groqWhisper"
    case openAIWhisper = "openAIWhisper"
    case appleNative = "appleNative"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .geminiFlash: return "✨ Gemini 2.0 Flash AI (Recommended)"
        case .groqWhisper: return "⚡️ Groq Whisper Large v3 (Ultra Fast)"
        case .openAIWhisper: return "🤖 OpenAI Whisper"
        case .appleNative: return "🍏 Apple Native Speech (Offline & Free)"
        }
    }
    
    public var shortName: String {
        switch self {
        case .geminiFlash: return "Gemini AI"
        case .groqWhisper: return "Groq Whisper"
        case .openAIWhisper: return "OpenAI"
        case .appleNative: return "Apple Offline"
        }
    }
}

public enum WisprLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case hinglish = "hinglish"
    case english = "english"
    case hindi = "hindi"
    case auto = "auto"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .hinglish: return "🇮🇳 Hinglish (Hindi + English Romanized)"
        case .english: return "🇬🇧 English (Global / US / UK)"
        case .hindi: return "🇮🇳 Pure Hindi (Devanagari)"
        case .auto: return "🌐 Auto-Detect Language"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .hinglish: return "Hinglish 🇮🇳"
        case .english: return "English 🇬🇧"
        case .hindi: return "Hindi 🇮🇳"
        case .auto: return "Auto 🌐"
        }
    }
    
    public var localeIdentifier: String {
        switch self {
        case .hinglish: return "en-IN" // Indian English tuned for Hinglish pronunciation
        case .english: return "en-US"
        case .hindi: return "hi-IN"
        case .auto: return "en-US"
        }
    }
}

public struct WisprDictationItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let engine: String
    public let language: String
    public let duration: Double
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        text: String,
        engine: String,
        language: String,
        duration: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.engine = engine
        self.language = language
        self.duration = duration
        self.createdAt = createdAt
    }
    
    public var formattedTime: String {
        let elapsed = Int(Date().timeIntervalSince(createdAt))
        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            return "\(elapsed / 60)m ago"
        } else if elapsed < 86400 {
            return "\(elapsed / 3600)h ago"
        } else {
            return "\(elapsed / 86400)d ago"
        }
    }
}

public final class WisprFlowService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = WisprFlowService()
    
    // UserDefaults Keys
    private let keyEnabled = "switch.wisprFlow.enabled"
    private let keyEngine = "switch.wisprFlow.engine"
    private let keyLanguage = "switch.wisprFlow.language"
    private let keyAutoPaste = "switch.wisprFlow.autoPaste"
    private let keyAutoPressReturn = "switch.wisprFlow.autoPressReturn"
    private let keyRemoveFillers = "switch.wisprFlow.removeFillers"
    private let keyAutoFormat = "switch.wisprFlow.autoFormat"
    private let keySoundFeedback = "switch.wisprFlow.soundFeedback"
    private let keyGeminiApiKey = "switch.wisprFlow.geminiApiKey"
    private let keyGroqApiKey = "switch.wisprFlow.groqApiKey"
    private let keyOpenAIApiKey = "switch.wisprFlow.openAIApiKey"
    private let keyHistory = "switch.wisprFlow.history"
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var audioLevels: [CGFloat] = [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]
    @Published public private(set) var statusMessage: String = "Ready"
    @Published public private(set) var lastTranscribedText: String = ""
    @Published public var recentDictations: [WisprDictationItem] = []
    
    @Published public var engine: WisprEngine = .geminiFlash {
        didSet {
            UserDefaults.standard.set(engine.rawValue, forKey: keyEngine)
        }
    }
    
    @Published public var language: WisprLanguage = .hinglish {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: keyLanguage)
        }
    }
    
    @Published public var autoPaste: Bool = true {
        didSet {
            UserDefaults.standard.set(autoPaste, forKey: keyAutoPaste)
        }
    }
    
    @Published public var autoPressReturn: Bool = false {
        didSet {
            UserDefaults.standard.set(autoPressReturn, forKey: keyAutoPressReturn)
        }
    }
    
    @Published public var removeFillerWords: Bool = true {
        didSet {
            UserDefaults.standard.set(removeFillerWords, forKey: keyRemoveFillers)
        }
    }
    
    @Published public var autoFormatPunctuation: Bool = true {
        didSet {
            UserDefaults.standard.set(autoFormatPunctuation, forKey: keyAutoFormat)
        }
    }
    
    @Published public var soundFeedback: Bool = true {
        didSet {
            UserDefaults.standard.set(soundFeedback, forKey: keySoundFeedback)
        }
    }
    
    @Published public var geminiApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: keyGeminiApiKey)
        }
    }
    
    @Published public var groqApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(groqApiKey, forKey: keyGroqApiKey)
        }
    }
    
    @Published public var openAIApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(openAIApiKey, forKey: keyOpenAIApiKey)
        }
    }
    
    // Audio engine & buffers
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var recordedAudioURL: URL?
    private var recordingTimer: Timer?
    private var levelSmoothingTimer: Timer?
    private var currentRMSPower: Float = 0.0
    
    // Floating HUD Panel
    private var hudWindow: NSPanel?
    private var historyWindow: NSWindow?
    
    // Global shortcut event monitor
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var lastOptionSpaceTime: TimeInterval = 0
    private var lastF8Time: TimeInterval = 0
    
    public var statusSubtitle: String? {
        if isListening {
            let m = Int(recordingDuration) / 60
            let s = Int(recordingDuration) % 60
            return String(format: "🎙️ Dictating %02d:%02d", m, s)
        } else if isProcessing {
            return "✨ AI Transcribing..."
        } else if isEnabled {
            return "\(language.shortLabel) · \(engine.shortName)"
        }
        return nil
    }
    
    private override init() {
        super.init()
        loadSettings()
        setupGlobalShortcutListeners()
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: keyEnabled)
        
        if let savedEngine = defaults.string(forKey: keyEngine), let e = WisprEngine(rawValue: savedEngine) {
            self.engine = e
        } else {
            self.engine = .geminiFlash
        }
        
        if let savedLang = defaults.string(forKey: keyLanguage), let l = WisprLanguage(rawValue: savedLang) {
            self.language = l
        } else {
            self.language = .hinglish
        }
        
        if defaults.object(forKey: keyAutoPaste) != nil {
            self.autoPaste = defaults.bool(forKey: keyAutoPaste)
        } else {
            self.autoPaste = true
        }
        
        if defaults.object(forKey: keyAutoPressReturn) != nil {
            self.autoPressReturn = defaults.bool(forKey: keyAutoPressReturn)
        } else {
            self.autoPressReturn = false
        }
        
        if defaults.object(forKey: keyRemoveFillers) != nil {
            self.removeFillerWords = defaults.bool(forKey: keyRemoveFillers)
        } else {
            self.removeFillerWords = true
        }
        
        if defaults.object(forKey: keyAutoFormat) != nil {
            self.autoFormatPunctuation = defaults.bool(forKey: keyAutoFormat)
        } else {
            self.autoFormatPunctuation = true
        }
        
        if defaults.object(forKey: keySoundFeedback) != nil {
            self.soundFeedback = defaults.bool(forKey: keySoundFeedback)
        } else {
            self.soundFeedback = true
        }
        
        self.geminiApiKey = defaults.string(forKey: keyGeminiApiKey) ?? ""
        self.groqApiKey = defaults.string(forKey: keyGroqApiKey) ?? ""
        self.openAIApiKey = defaults.string(forKey: keyOpenAIApiKey) ?? ""
        
        loadHistory()
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: keyHistory),
           let items = try? JSONDecoder().decode([WisprDictationItem].self, from: data) {
            self.recentDictations = items
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentDictations) {
            UserDefaults.standard.set(data, forKey: keyHistory)
        }
    }
    
    public func addHistoryItem(text: String, duration: Double) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = WisprDictationItem(
            text: text,
            engine: engine.shortName,
            language: language.shortLabel,
            duration: duration
        )
        recentDictations.insert(item, at: 0)
        if recentDictations.count > 40 {
            recentDictations = Array(recentDictations.prefix(40))
        }
        saveHistory()
    }
    
    public func clearHistory() {
        recentDictations.removeAll()
        saveHistory()
    }
    
    // MARK: - Master Toggle
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: keyEnabled)
        
        if enabled {
            playChime(name: "Blow")
        } else {
            if isListening {
                cancelRecording()
            }
        }
        
        NotificationCenter.default.post(name: .wisprFlowStateDidChange, object: enabled)
    }
    
    // MARK: - Global Shortcut Listeners (Hold 'L' Key for 2s to Dictate, Release to Paste & Return, plus F8 toggle)
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isLKeyHeld: Bool = false
    private var isLDictationActive: Bool = false
    private var lKeyHoldWorkItem: DispatchWorkItem?
    
    private func setupGlobalShortcutListeners() {
        // 1. Global monitor for key down, key up, and systemDefined media keys
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .systemDefined]) { [weak self] event in
            self?.handleNSEvent(event)
        }
        
        // 2. Local monitor for when Switch is active
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .systemDefined]) { [weak self] event in
            if let self = self {
                if event.type == .keyDown {
                    if event.keyCode == 37 {
                        let hasMod = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option)
                        self.handleLKeyDown(hasModifiers: hasMod)
                    } else if self.isF8Event(event) || self.isOptionSpaceEvent(event) {
                        self.recordF8Press()
                        return nil
                    } else if self.isLKeyHeld && !self.isLDictationActive {
                        self.cancelLKeyTimer()
                    }
                } else if event.type == .keyUp {
                    if event.keyCode == 37 {
                        self.handleLKeyUp()
                    }
                }
            }
            return event
        }
        
        // 3. CoreGraphics Event Tap to intercept physical L hold and F8
        setupEventTap()
    }
    
    private func setupEventTap() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard WisprFlowService.shared.isEnabled else {
                    return Unmanaged.passUnretained(event)
                }
                
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                
                // Track 'L' key (keycode 37)
                if keycode == 37 {
                    if type == .keyDown {
                        let flags = event.flags
                        let hasMod = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                        if hasMod {
                            WisprFlowService.shared.cancelLKeyTimer()
                            return Unmanaged.passUnretained(event)
                        }
                        
                        // If already dictating or in the middle of 1s hold, suppress repeat 'l' keypresses
                        if WisprFlowService.shared.isLDictationActive || WisprFlowService.shared.isLKeyHeld {
                            return nil // consume event so macOS does not type 'lllllll...'
                        }
                        
                        WisprFlowService.shared.handleLKeyDown(hasModifiers: false)
                        return Unmanaged.passUnretained(event)
                    } else if type == .keyUp {
                        let wasDictating = WisprFlowService.shared.isLDictationActive
                        WisprFlowService.shared.handleLKeyUp()
                        if wasDictating {
                            return nil // consume keyUp so no trailing character is posted
                        }
                        return Unmanaged.passUnretained(event)
                    }
                } else if type == .keyDown {
                    if WisprFlowService.shared.isLKeyHeld && !WisprFlowService.shared.isLDictationActive {
                        WisprFlowService.shared.cancelLKeyTimer()
                    }
                    
                    // Check standard F8 (keycode 100)
                    if keycode == 100 {
                        if WisprFlowService.shared.recordF8Press() {
                            return nil // consume event
                        }
                    }
                }
                
                // Check System-Defined media key for F8 (Play/Pause keycode 16 on Mac keyboards without Fn)
                if type.rawValue == 14 {
                    if let nsEvent = NSEvent(cgEvent: event),
                       nsEvent.type == .systemDefined,
                       nsEvent.subtype.rawValue == 8 {
                        let data = nsEvent.data1
                        let keyCode = Int((data & 0xFFFF0000) >> 16)
                        let keyFlags = data & 0x0000FFFF
                        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
                        let isRepeat = (keyFlags & 0x1) != 0
                        
                        // 16 is NX_KEYTYPE_PLAY (physical F8 key on MacBook keyboards without Fn)
                        if keyCode == 16 && isKeyDown && !isRepeat {
                            if WisprFlowService.shared.recordF8Press() {
                                return nil // consume event so Music app doesn't open
                            }
                        }
                    }
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    public func handleLKeyDown(hasModifiers: Bool) {
        guard isEnabled else { return }
        if hasModifiers {
            cancelLKeyTimer()
            return
        }
        
        guard !isLKeyHeld else { return }
        isLKeyHeld = true
        
        // Start 1.0 second hold timer
        lKeyHoldWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isLKeyHeld, self.isEnabled else { return }
            self.isLDictationActive = true
            
            // Delete the initial 'l' character that was typed when L was first pressed
            DispatchQueue.main.async {
                let src = CGEventSource(stateID: .hidSystemState)
                let deleteKeyCode: CGKeyCode = 51 // kVK_Delete (Backspace)
                if let delDown = CGEvent(keyboardEventSource: src, virtualKey: deleteKeyCode, keyDown: true),
                   let delUp = CGEvent(keyboardEventSource: src, virtualKey: deleteKeyCode, keyDown: false) {
                    delDown.flags = []
                    delUp.flags = []
                    delDown.post(tap: .cghidEventTap)
                    delUp.post(tap: .cghidEventTap)
                }
                self.startRecording()
            }
        }
        self.lKeyHoldWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
    
    public func handleLKeyUp() {
        guard isEnabled else { return }
        isLKeyHeld = false
        lKeyHoldWorkItem?.cancel()
        lKeyHoldWorkItem = nil
        
        if isLDictationActive {
            isLDictationActive = false
            if isListening {
                DispatchQueue.main.async { [weak self] in
                    self?.stopAndTranscribe()
                }
            }
        }
    }
    
    public func cancelLKeyTimer() {
        isLKeyHeld = false
        lKeyHoldWorkItem?.cancel()
        lKeyHoldWorkItem = nil
        if isLDictationActive {
            isLDictationActive = false
            if isListening {
                DispatchQueue.main.async { [weak self] in
                    self?.cancelRecording()
                }
            }
        }
    }
    
    private func handleNSEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 37 {
                let hasMod = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option)
                handleLKeyDown(hasModifiers: hasMod)
            } else if isF8Event(event) || isOptionSpaceEvent(event) {
                _ = recordF8Press()
            } else if isLKeyHeld && !isLDictationActive {
                cancelLKeyTimer()
            }
        } else if event.type == .keyUp {
            if event.keyCode == 37 {
                handleLKeyUp()
            }
        }
    }
    
    private func isF8Event(_ event: NSEvent) -> Bool {
        // Standard F8 key
        if event.type == .keyDown && event.keyCode == 100 {
            return true
        }
        
        // System Defined Media Key for F8 (Play/Pause key on MacBook keyboards without Fn)
        if event.type == .systemDefined && event.subtype.rawValue == 8 {
            let data = event.data1
            let keyCode = Int((data & 0xFFFF0000) >> 16)
            let keyFlags = data & 0x0000FFFF
            let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
            let isRepeat = (keyFlags & 0x1) != 0
            if keyCode == 16 && isKeyDown && !isRepeat {
                return true
            }
        }
        
        return false
    }
    
    private func isOptionSpaceEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 49 && event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            return true
        }
        return false
    }
    
    @discardableResult
    public func recordF8Press() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = now - lastF8Time
        
        if delta > 0.25 {
            lastF8Time = now
            DispatchQueue.main.async { [weak self] in
                self?.toggleDictation()
            }
            return true
        }
        return false
    }
    
    // MARK: - Dictation Flow Control
    
    public func toggleDictation() {
        if isListening {
            stopAndTranscribe()
        } else if !isProcessing {
            startRecording()
        }
    }
    
    public func startRecording() {
        guard !isListening && !isProcessing else { return }
        
        // Request Microphone access if needed
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.checkSpeechAndBegin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.checkSpeechAndBegin()
                    } else {
                        self?.showMicrophoneAccessAlert()
                    }
                }
            }
        case .denied, .restricted:
            showMicrophoneAccessAlert()
        @unknown default:
            break
        }
    }
    
    private func checkSpeechAndBegin() {
        // If using Apple Native speech recognizer, verify speech recognition permission
        if engine == .appleNative || (geminiApiKey.isEmpty && groqApiKey.isEmpty && openAIApiKey.isEmpty) {
            let status = SFSpeechRecognizer.authorizationStatus()
            if status == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { [weak self] auth in
                    DispatchQueue.main.async {
                        if auth == .authorized {
                            self?.beginAudioEngineCapture()
                        } else {
                            self?.showSpeechRecognitionAccessAlert()
                        }
                    }
                }
                return
            } else if status == .denied || status == .restricted {
                showSpeechRecognitionAccessAlert()
                return
            }
        }
        
        self.beginAudioEngineCapture()
    }
    
    private func beginAudioEngineCapture() {
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            
            // Temporary WAV recording file
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let fileURL = tempDir.appendingPathComponent("wispr_flow_\(UUID().uuidString).wav")
            self.recordedAudioURL = fileURL
            
            // Format for voice dictation: 16kHz Mono Float32/PCM
            guard let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
                throw NSError(domain: "WisprFlow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize 16kHz audio format"])
            }
            
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            self.audioFile = audioFile
            
            // Downmix / convert input buffer to 16kHz mono format
            guard let converter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
                throw NSError(domain: "WisprFlow", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio converter creation failed"])
            }
            
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                guard let self = self else { return }
                
                // Adaptive sensitivity boost (2.5x gain with soft limiting) to capture low voices & whispers clearly
                let boostMultiplier: Float = 2.5
                var sum: Float = 0.0
                let frameLength = Int(buffer.frameLength)
                
                if let channelData = buffer.floatChannelData?[0] {
                    for i in 0..<frameLength {
                        let boosted = channelData[i] * boostMultiplier
                        let clamped = max(-1.0, min(1.0, boosted))
                        channelData[i] = clamped
                        sum += clamped * clamped
                    }
                }
                let rms = sqrt(sum / max(1, Float(frameLength)))
                self.currentRMSPower = rms
                
                // Convert buffer to 16kHz Int16 format and write to file
                let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate) + 100)!
                var error: NSError? = nil
                
                var isDone = false
                converter.convert(to: convertedBuffer, error: &error) { packetCount, outStatus in
                    if !isDone {
                        isDone = true
                        outStatus.pointee = .haveData
                        return buffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }
                
                if let audioFile = self.audioFile, convertedBuffer.frameLength > 0 {
                    try? audioFile.write(from: convertedBuffer)
                }
            }
            
            try engine.start()
            self.audioEngine = engine
            self.inputNode = input
            
            self.isListening = true
            self.recordingDuration = 0
            self.statusMessage = "Listening..."
            
            if soundFeedback {
                playChime(name: "Tink")
            }
            
            // Start duration and waveform timers
            startTimers()
            showHUD()
            
            NotificationCenter.default.post(name: .wisprFlowListeningDidChange, object: true)
            
        } catch {
            print("WisprFlow audio capture error: \(error.localizedDescription)")
            self.statusMessage = "Audio Error"
            playChime(name: "Basso")
        }
    }
    
    private func startTimers() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isListening else { return }
            self.recordingDuration += 0.1
        }
        
        levelSmoothingTimer?.invalidate()
        levelSmoothingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, self.isListening else { return }
            self.updateWaveformBars()
        }
    }
    
    private func stopTimers() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        levelSmoothingTimer?.invalidate()
        levelSmoothingTimer = nil
    }
    
    private func updateWaveformBars() {
        let power = CGFloat(min(1.0, max(0.04, currentRMSPower * 14.0)))
        
        // Simulate organic reactive heights across 7 visualizer bars
        var newLevels: [CGFloat] = []
        let factors: [CGFloat] = [0.45, 0.75, 1.0, 0.9, 1.05, 0.70, 0.40]
        for f in factors {
            let jitter = CGFloat.random(in: 0.85...1.15)
            let val = min(1.0, max(0.08, power * f * jitter))
            newLevels.append(val)
        }
        
        DispatchQueue.main.async {
            self.audioLevels = newLevels
        }
    }
    
    public func cancelRecording() {
        cleanupAudioEngine()
        isListening = false
        isProcessing = false
        statusMessage = "Cancelled"
        hideHUD(delay: 0.2)
        NotificationCenter.default.post(name: .wisprFlowListeningDidChange, object: false)
    }
    
    public func stopAndTranscribe() {
        guard isListening else { return }
        
        let finalDuration = recordingDuration
        cleanupAudioEngine()
        isListening = false
        isProcessing = true
        statusMessage = "AI Processing..."
        
        if soundFeedback {
            playChime(name: "Pop")
        }
        
        NotificationCenter.default.post(name: .wisprFlowListeningDidChange, object: false)
        
        guard let url = recordedAudioURL, FileManager.default.fileExists(atPath: url.path) else {
            self.isProcessing = false
            self.statusMessage = "No Audio Captured"
            self.hideHUD(delay: 1.0)
            return
        }
        
        // Execute AI Speech Recognition Pipeline in background
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let transcribed = try await self.executeTranscriptionPipeline(audioURL: url, duration: finalDuration)
                await MainActor.run {
                    self.isProcessing = false
                    let cleanText = self.postProcessTranscription(transcribed, language: self.language)
                    
                    if !cleanText.isEmpty {
                        self.lastTranscribedText = cleanText
                        self.statusMessage = "Transcribed!"
                        self.addHistoryItem(text: cleanText, duration: finalDuration)
                        
                        if self.autoPaste {
                            self.pasteTranscribedText(cleanText)
                        } else {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cleanText, forType: .string)
                        }
                        
                        if self.soundFeedback {
                            self.playChime(name: "Glass")
                        }
                        
                        NotificationCenter.default.post(name: .wisprFlowDidTranscribe, object: cleanText)
                        self.hideHUD(delay: 1.2)
                    } else {
                        self.statusMessage = "No speech detected"
                        self.hideHUD(delay: 1.0)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.statusMessage = "Error: \(error.localizedDescription)"
                    print("Transcription failed: \(error.localizedDescription)")
                    if self.soundFeedback {
                        self.playChime(name: "Basso")
                    }
                    self.hideHUD(delay: 2.0)
                }
            }
        }
    }
    
    private func cleanupAudioEngine() {
        stopTimers()
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        audioFile = nil
    }
    
    // MARK: - Multi-Engine Speech-to-Text Pipeline
    
    private func executeTranscriptionPipeline(audioURL: URL, duration: Double) async throws -> String {
        // Read raw audio file data
        let audioData = try Data(contentsOf: audioURL)
        
        switch engine {
        case .geminiFlash:
            if !geminiApiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                return try await transcribeWithGemini(audioData: audioData, language: language)
            } else {
                // Seamless fallback to Apple Native Speech if no API key provided
                return try await transcribeWithAppleSpeech(audioURL: audioURL, language: language)
            }
            
        case .groqWhisper:
            if !groqApiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                return try await transcribeWithGroq(audioData: audioData, language: language)
            } else {
                return try await transcribeWithAppleSpeech(audioURL: audioURL, language: language)
            }
            
        case .openAIWhisper:
            if !openAIApiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                return try await transcribeWithOpenAI(audioData: audioData, language: language)
            } else {
                return try await transcribeWithAppleSpeech(audioURL: audioURL, language: language)
            }
            
        case .appleNative:
            return try await transcribeWithAppleSpeech(audioURL: audioURL, language: language)
        }
    }
    
    // MARK: - Engine 1: Google Gemini Flash Audio AI (Highest Accuracy for Hinglish & English)
    
    private func transcribeWithGemini(audioData: Data, language: WisprLanguage) async throws -> String {
        let apiKey = geminiApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "WisprFlow", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Gemini API Key"])
        }
        
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25.0
        
        let base64Audio = audioData.base64EncodedString()
        
        let promptText: String
        switch language {
        case .hinglish:
            promptText = """
            You are Wispr Flow, the world's most accurate voice dictation engine specialized in Hinglish (Hindi + English mixed together).
            Transcribe this audio into clean text.
            CRITICAL HINGLISH TRANSCRIPTION RULES:
            1. Transcribe Hindi speech in clean, natural Roman script (English alphabet). NEVER use Devanagari.
            2. Common examples:
               - "main nahi karunga" (NOT "kanga")
               - "main nahi kahunga"
               - "main seekhunga" (NOT "sikha ga")
               - "kya haal hai bhai kal milte hain"
               - "meeting 5 baje schedule kar do"
               - "client ko email send kar diya"
            3. Write English technical & colloquial words in standard English spelling (e.g. meeting, schedule, delivery, email, code, bug, website, laptop, call, okay, thanks).
            4. Remove filler words ("um", "uh", "matlab", "basically", "you know", "like") and stammers.
            5. Add proper punctuation, Auto-Shift capitalization, and clean formatting.
            6. Output ONLY the plain transcribed text without markdown formatting, quotes, or explanations.
            """
        case .english:
            promptText = """
            You are Wispr Flow, the world's most accurate voice dictation engine.
            Transcribe this audio into clean English.
            1. Remove filler words ("um", "uh", "you know", "like") and fix stammers.
            2. Add accurate punctuation, capitalization, and formatting.
            3. Output ONLY the raw transcribed text.
            """
        case .hindi:
            promptText = """
            You are Wispr Flow voice dictation engine.
            Transcribe this audio accurately into Hindi (Devanagari script) with clean punctuation and no filler words. Output ONLY the raw text.
            """
        case .auto:
            promptText = """
            You are Wispr Flow voice dictation engine.
            Transcribe this audio accurately in the exact language/mix spoken (if Hinglish, write Hindi words in Roman script and English in English). Add clean punctuation and remove filler words. Output ONLY the raw text.
            """
        }
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": promptText
                        ],
                        [
                            "inline_data": [
                                "mime_type": "audio/wav",
                                "data": base64Audio
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 2048
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResp = response as? HTTPURLResponse else {
            throw NSError(domain: "WisprFlow", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        guard httpResp.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "Unknown HTTP \(httpResp.statusCode)"
            throw NSError(domain: "WisprFlow", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini API Error (\(httpResp.statusCode)): \(errBody)"])
        }
        
        // Parse Gemini JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "WisprFlow", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Gemini transcription"])
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Engine 2: Groq Whisper Large v3 (Fastest Latency)
    
    private func transcribeWithGroq(audioData: Data, language: WisprLanguage) async throws -> String {
        let apiKey = groqApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "WisprFlow", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing Groq API Key"])
        }
        
        let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20.0
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3\r\n".data(using: .utf8)!)
        
        // prompt parameter
        let promptText = (language == .hinglish) ? "Hinglish (Hindi spoken with English words in Roman script, e.g. Main nahi karunga, seekhunga) with clean punctuation." : "English dictation with clean punctuation."
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(promptText)\r\n".data(using: .utf8)!)
        
        // response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // temperature
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
        body.append("0.0\r\n".data(using: .utf8)!)
        
        // file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let err = String(data: data, encoding: .utf8) ?? "Groq Error"
            throw NSError(domain: "WisprFlow", code: -5, userInfo: [NSLocalizedDescriptionKey: "Groq error: \(err)"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw NSError(domain: "WisprFlow", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Groq transcription"])
    }
    
    // MARK: - Engine 3: OpenAI Whisper
    
    private func transcribeWithOpenAI(audioData: Data, language: WisprLanguage) async throws -> String {
        let apiKey = openAIApiKey.trimmingCharacters(in: .whitespaces)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "WisprFlow", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API Key"])
        }
        
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20.0
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        let promptText = (language == .hinglish) ? "Hinglish transcription in Roman script (Main nahi karunga, seekhunga) with proper punctuation." : "English dictation."
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(promptText)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let err = String(data: data, encoding: .utf8) ?? "OpenAI Error"
            throw NSError(domain: "WisprFlow", code: -7, userInfo: [NSLocalizedDescriptionKey: "OpenAI error: \(err)"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw NSError(domain: "WisprFlow", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse OpenAI transcription"])
    }
    
    // MARK: - Engine 4: Apple Native Speech Recognizer (100% Offline & Free)
    
    private func transcribeWithAppleSpeech(audioURL: URL, language: WisprLanguage) async throws -> String {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted {
                await MainActor.run {
                    self.showSpeechRecognitionAccessAlert()
                }
                throw NSError(domain: "WisprFlow", code: 403, userInfo: [NSLocalizedDescriptionKey: "Speech Recognition permission not granted"])
            }
        } else if authStatus == .denied || authStatus == .restricted {
            await MainActor.run {
                self.showSpeechRecognitionAccessAlert()
            }
            throw NSError(domain: "WisprFlow", code: 403, userInfo: [NSLocalizedDescriptionKey: "Speech Recognition permission denied. Please allow Switch in System Settings > Privacy & Security > Speech Recognition."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let targetLocale = (language == .hinglish) ? "hi-IN" : language.localeIdentifier
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: targetLocale)) 
                ?? SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)) 
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            
            guard let recognizer = recognizer, recognizer.isAvailable else {
                continuation.resume(throwing: NSError(domain: "WisprFlow", code: -9, userInfo: [NSLocalizedDescriptionKey: "Apple Speech Recognizer unavailable"]))
                return
            }
            
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            request.addsPunctuation = true
            
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result, result.isFinal {
                    var text = result.bestTranscription.formattedString
                    
                    // Transliterate any Devanagari Hindi output to clean Romanized Hinglish
                    if language == .hinglish || language == .auto {
                        text = DevanagariToRomanTransliterater.transliterate(text)
                    }
                    
                    if self.removeFillerWords {
                        text = self.cleanUpFillerWords(text)
                    }
                    continuation.resume(returning: text)
                }
            }
        }
    }
    
    public func postProcessTranscription(_ text: String, language: WisprLanguage) -> String {
        var processed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else { return "" }
        
        // 1. Transliterate Devanagari to Romanized Hinglish if applicable
        if language == .hinglish || language == .auto {
            processed = DevanagariToRomanTransliterater.transliterate(processed)
        }
        
        // 2. Remove filler words if enabled
        if removeFillerWords {
            processed = cleanUpFillerWords(processed)
        }
        
        // 3. Fix Hinglish specific phonetic errors & unwanted commas
        if language == .hinglish || language == .auto {
            processed = cleanUpHinglishPhoneticsAndCommas(processed)
        }
        
        // 4. Auto-format punctuation and capitalization if enabled
        if autoFormatPunctuation {
            processed = cleanUpPunctuationAndFormatting(processed)
        }
        
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanUpFillerWords(_ text: String) -> String {
        var cleaned = text
        let fillers = ["um", "uh", "er", "ah", "matlab", "basically", "you know"]
        for f in fillers {
            let pattern = "\\b\(f)\\b[,\\s]*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: "")
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanUpHinglishPhoneticsAndCommas(_ text: String) -> String {
        var result = text
        
        // Comprehensive phonetic dictionary fixes for acoustic speech recognizer mishearings
        let phoneticReplacements: [(String, String)] = [
            ("(?i)\\bmain\\s+nahi\\s+kanga\\b", "Main nahi kahunga"),
            ("(?i)\\bnahi\\s+kanga\\b", "nahi kahunga"),
            ("(?i)\\bmain\\s+sikha\\s+ga\\b", "Main seekhunga"),
            ("(?i)\\bsikha\\s+ga\\b", "seekhega"),
            ("(?i)\\bsikha\\s+ja\\b", "seekha"),
            ("(?i)\\bkaruga\\b", "karunga"),
            ("(?i)\\bkarugi\\b", "karungi"),
            ("(?i)\\bboluga\\b", "bolunga"),
            ("(?i)\\bdekhuga\\b", "dekhunga"),
            ("(?i)\\bsunuga\\b", "sununga"),
            ("(?i)\\bbatao\\s*ga\\b", "bataunga"),
            ("(?i)\\bchala\\s*ga\\b", "chalega"),
            ("(?i)\\bchali\\s*gi\\b", "chalegi"),
            ("(?i)\\baaye\\s*ga\\b", "aayega"),
            ("(?i)\\bjaaye\\s*ga\\b", "jaayega"),
            ("(?i)\\bkare\\s*ga\\b", "karega"),
            ("(?i)\\bbole\\s*ga\\b", "bolega"),
            ("(?i)\\bdekhe\\s*ga\\b", "dekhega"),
            ("(?i)\\bsune\\s*ga\\b", "sunega"),
            ("(?i)\\bkar\\s+duga\\b", "kar dunga"),
            ("(?i)\\bde\\s+duga\\b", "de dunga"),
            ("(?i)\\ble\\s+duga\\b", "le dunga"),
            ("(?i)\\bbhej\\s+duga\\b", "bhej dunga"),
            ("(?i)\\bmera,\\s*nama\\s+hai\\b", "Mera naam hai"),
            ("(?i)\\bmera,\\s*naam\\s+hai\\b", "Mera naam hai"),
            ("(?i)\\bmera\\s+nama\\s+hai\\b", "Mera naam hai"),
            ("(?i)\\bmera,\\s*nama\\b", "mera naam"),
            ("(?i)\\bmera\\s+nama\\b", "mera naam"),
            ("(?i)\\btera,\\s*nama\\b", "tera naam"),
            ("(?i)\\btera\\s+nama\\b", "tera naam"),
            ("(?i)\\bapna,\\s*nama\\b", "apna naam"),
            ("(?i)\\bapna\\s+nama\\b", "apna naam"),
            ("(?i)\\buska,\\s*nama\\b", "uska naam"),
            ("(?i)\\buska\\s+nama\\b", "uska naam"),
            ("(?i)\\bkya,\\s*nama\\b", "kya naam"),
            ("(?i)\\bkya\\s+nama\\b", "kya naam"),
            ("(?i)\\bnama\\s+hai\\b", "naam hai"),
            ("(?i)\\bnama\\s+kya\\b", "naam kya")
        ]
        
        for (pattern, template) in phoneticReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: template)
            }
        }
        
        // Remove misplaced commas after common Hindi pronouns/conjunctions/words
        let commaPatterns: [String] = [
            "(?i)\\b(mera|tera|apna|uska|humara|tumhara|unka|kya|kyun|kaise|kab|kahan|yeh|woh|main|hum|aap|tum|bhi|nahi|nahin|toh|par|aur|ki|ke|ko|se|me|mein)\\s*,\\s*(?=[a-zA-Z0-9])"
        ]
        for pattern in commaPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "$1 ")
            }
        }
        
        return result
    }
    
    private func cleanUpPunctuationAndFormatting(_ text: String) -> String {
        var result = text
        
        // Remove space before punctuation: "word , text" -> "word, text"
        if let regex = try? NSRegularExpression(pattern: "\\s+([,\\.!\\?;:])", options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "$1")
        }
        
        // Fix multiple commas: ",," or ", ," -> ","
        if let regex = try? NSRegularExpression(pattern: ",[\\s,]+", options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: ", ")
        }
        
        // Fix comma before period: ",." -> "."
        if let regex = try? NSRegularExpression(pattern: ",\\s*\\.", options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: ".")
        }
        
        // Remove trailing commas or colons at the end of the transcription
        if let regex = try? NSRegularExpression(pattern: "[,;:]+$", options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        
        // Auto Shift 1: Capitalize after sentence boundaries (. ? ! \n)
        if let regex = try? NSRegularExpression(pattern: "(^|[\\.?!\\n]\\s+)([a-z])", options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result) {
                    let matchedStr = String(result[range])
                    let capitalized = matchedStr.uppercased()
                    result.replaceSubrange(range, with: capitalized)
                }
            }
        }
        
        // Auto Shift 2: Capitalize standalone 'i' pronoun & contractions (i -> I, i'm -> I'm, i'll -> I'll, i've -> I've, i'd -> I'd)
        let pronounFixes: [(String, String)] = [
            ("(?i)\\bi\\b", "I"),
            ("(?i)\\bi'm\\b", "I'm"),
            ("(?i)\\bi'll\\b", "I'll"),
            ("(?i)\\bi've\\b", "I've"),
            ("(?i)\\bi'd\\b", "I'd")
        ]
        for (pat, repl) in pronounFixes {
            if let regex = try? NSRegularExpression(pattern: pat, options: []) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: repl)
            }
        }
        
        // Auto Shift 3: Capitalize proper nouns, brands, days, and tech terms
        let properNouns = [
            "Google", "Apple", "Mac", "MacBook", "iPhone", "iPad", "Switch", "WhatsApp", "YouTube",
            "Instagram", "Telegram", "LinkedIn", "Twitter", "Slack", "Zoom", "Gmail", "GitHub",
            "Microsoft", "Windows", "Android", "ChatGPT", "Gemini", "Amazon", "Netflix",
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
            "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
            "India", "Delhi", "Mumbai", "Bangalore", "Bengaluru", "Hyderabad", "Pune", "Kolkata", "Chennai", "Noida", "Gurgaon", "Jaipur", "Goa"
        ]
        for noun in properNouns {
            if let regex = try? NSRegularExpression(pattern: "(?i)\\b\(noun)\\b", options: []) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: noun)
            }
        }
        
        // Ensure first character of entire transcription is capitalized
        if let first = result.first, first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Auto-Paste Emulation (⌘V Keypress & Optional Return)
    
    public func pasteTranscribedText(_ text: String) {
        // Strip trailing/leading whitespace and linebreaks so paste does not trigger submit
        var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while sanitized.hasSuffix("\n") || sanitized.hasSuffix("\r") {
            sanitized = String(sanitized.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !sanitized.isEmpty else { return }
        
        // Copy to system clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(sanitized, forType: .string)
        
        // Emulate ⌘V keystroke via CGEvent into the frontmost app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            let src = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 9 // 'v' key
            
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else {
                return
            }
            
            keyDown.flags = .maskCommand
            keyUp.flags = []
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            
            // Only press Return if the user explicitly enabled autoPressReturn in Settings
            if self.autoPressReturn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let returnKeyCode: CGKeyCode = 36 // kVK_Return
                    guard let returnDown = CGEvent(keyboardEventSource: src, virtualKey: returnKeyCode, keyDown: true),
                          let returnUp = CGEvent(keyboardEventSource: src, virtualKey: returnKeyCode, keyDown: false) else {
                        return
                    }
                    returnDown.flags = []
                    returnUp.flags = []
                    returnDown.post(tap: .cghidEventTap)
                    returnUp.post(tap: .cghidEventTap)
                }
            }
        }
    }
    
    // MARK: - Floating Dynamic HUD
    
    public func showHUD() {
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 74),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hosting = NSHostingView(rootView: WisprFlowFloatingHUD())
            panel.contentView = hosting
            self.hudWindow = panel
        }
        
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 140
            let y = screen.visibleFrame.minY + 45
            hudWindow?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        hudWindow?.alphaValue = 0.0
        hudWindow?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            hudWindow?.animator().alphaValue = 1.0
        }
    }
    
    public func hideHUD(delay: TimeInterval = 0.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let hud = self.hudWindow else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                hud.animator().alphaValue = 0.0
            }, completionHandler: {
                hud.orderOut(nil)
            })
        }
    }
    
    // MARK: - History Window
    
    public func toggleHistoryWindow() {
        if let win = historyWindow, win.isVisible {
            win.orderOut(nil)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Wispr Flow Dictation History"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: WisprFlowHistoryView())
        self.historyWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func playChime(name: String) {
        if soundFeedback && AppSettings.shared.playSound {
            NSSound(named: name)?.play()
        }
    }
    
    private func showMicrophoneAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "Wispr Flow voice dictation needs access to your microphone to convert your speech into text. Please enable Microphone in macOS System Settings > Privacy & Security."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showSpeechRecognitionAccessAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Speech Recognition Permission Required"
            alert.informativeText = "Switch needs permission for Speech Recognition to convert your voice into text. Please allow Switch in macOS System Settings > Privacy & Security > Speech Recognition."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Devanagari Hindi to Romanized Hinglish Transliteration Engine

public enum DevanagariToRomanTransliterater {
    // High-frequency Hindi word dictionary for natural Roman spelling
    private static let wordMap: [String: String] = [
        "मैं": "Main", "मै": "Main", "नहीं": "nahi", "नही": "nahi",
        "करूँगा": "karunga", "करूंगा": "karunga", "करूंगी": "karungi", "करूँगी": "karungi", "करेगा": "karega", "करेंगे": "karenge",
        "सीखूँगा": "seekhunga", "सीखूंगा": "seekhunga", "सीखेंगे": "seekhenge", "सीखा": "seekha", "सीखेगा": "seekhega",
        "कहूँगा": "kahunga", "कहुंगा": "kahunga", "कहा": "kaha", "कहेगा": "kahega", "कहेंगे": "kahenge",
        "जाऊँगा": "jaunga", "जाऊंगा": "jaunga", "जाएंगे": "jaenge", "जाएगा": "jaayega", "गया": "gaya", "गए": "gaye",
        "आऊँगा": "aaunga", "आऊंगा": "aaunga", "आएंगे": "aayenge", "आएगा": "aayega", "आया": "aaya", "आए": "aaye",
        "बोलूँगा": "bolunga", "बोलूंगा": "bolunga", "बोला": "bola", "बोलेंगे": "bolenge",
        "देखूँगा": "dekhunga", "देखूंगा": "dekhunga", "देखा": "dekha", "देखेंगे": "dekhenge",
        "सुनूँगा": "sununga", "सुनूंगा": "sununga", "सुना": "suna", "सुनेंगे": "sunenge",
        "बताऊँगा": "bataunga", "बताऊंगा": "bataunga", "बताया": "bataya", "बताएंगे": "bataenge",
        "होगा": "hoga", "होगी": "hogi", "होंगे": "honge", "हुआ": "hua", "हुई": "hui", "हुए": "hue",
        "है": "hai", "हैं": "hain", "हो": "ho", "हूं": "hoon", "हूँ": "hoon",
        "था": "tha", "थी": "thi", "थे": "the",
        "क्या": "kya", "क्यों": "kyun", "क्यूँ": "kyun", "क्यूं": "kyun", "कैसे": "kaise", "कब": "kab", "कहाँ": "kahan", "किधर": "kidhar",
        "भाई": "bhai", "यार": "yaar", "दोस्त": "dost", "अच्छा": "achha", "अच्छी": "achhi", "ठीक": "theek",
        "बहुत": "bahut", "थोड़ा": "thoda", "ज्यादा": "zyada", "कम": "kam",
        "आप": "aap", "तुम": "tum", "हम": "hum", "वो": "woh", "वह": "woh", "यह": "yeh", "ये": "ye", "वे": "ve",
        "मेरा": "mera", "मेरी": "meri", "मेरे": "mere", "तेरा": "tera", "तेरी": "teri", "तेरे": "tere",
        "हमारा": "humara", "हमारी": "humari", "हमारे": "humare", "तुम्हारा": "tumhara", "तुम्हारी": "tumhari", "तुम्हारे": "tumhare",
        "उसका": "uska", "उसकी": "uski", "उसके": "uske", "उनका": "unka", "उनकी": "unki", "उनके": "unke",
        "इसका": "iska", "इसकी": "iski", "इसके": "iske", "इनका": "inka", "इनकी": "inki", "इनके": "inke",
        "कल": "kal", "आज": "aaj", "परसों": "parson", "सुबह": "subah", "शाम": "shaam", "रात": "raat", "दिन": "din",
        "समय": "samay", "काम": "kaam", "बात": "baat", "घर": "ghar", "ऑफिस": "office", "फोन": "phone",
        "पैसा": "paisa", "पैसे": "paise", "रुपये": "rupaye", "गाड़ी": "gaadi", "पानी": "paani", "खाना": "khaana",
        "और": "aur", "लेकिन": "lekin", "पर": "par", "अगर": "agar", "तो": "toh", "भी": "bhi", "तक": "tak",
        "के": "ke", "की": "ki", "का": "ka", "को": "ko", "से": "se", "में": "mein", "पे": "pe"
    ]
    
    public static func transliterate(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) else {
            return text
        }
        
        var result = text
        for (devanagari, roman) in wordMap {
            result = result.replacingOccurrences(of: devanagari, with: roman)
        }
        
        if result.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) }) {
            result = transliterateCharByChar(result)
        }
        
        return result
    }
    
    private static func transliterateCharByChar(_ input: String) -> String {
        let vowels: [Character: String] = [
            "अ": "a", "आ": "aa", "इ": "i", "ई": "ee", "उ": "u", "ऊ": "oo",
            "ऋ": "ri", "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au"
        ]
        let matras: [Character: String] = [
            "ा": "a", "ि": "i", "ी": "i", "ु": "u", "ू": "u", "ृ": "ri",
            "े": "e", "ै": "ai", "ो": "o", "ौ": "au"
        ]
        let consonants: [Character: String] = [
            "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "ng",
            "च": "ch", "छ": "chh", "ज": "j", "झ": "jh", "ञ": "ny",
            "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n",
            "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
            "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m",
            "य": "y", "र": "r", "ल": "l", "व": "v", "श": "sh", "ष": "sh", "स": "s", "ह": "h",
            "क़": "q", "ख़": "kh", "ग़": "gh", "ज़": "z", "ड़": "r", "ढ़": "rh", "फ़": "f"
        ]
        
        var out = ""
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let nextC = (i + 1 < chars.count) ? chars[i + 1] : nil
            
            if let vow = vowels[c] {
                out += vow
            } else if let mat = matras[c] {
                out += mat
            } else if c == "्" {
                // Halant/Virama suppresses inherent 'a'
            } else if c == "ं" || c == "ँ" {
                out += "n"
            } else if c == "ः" {
                out += "h"
            } else if c == "़" {
                // Nukta
            } else if let con = consonants[c] {
                out += con
                if let next = nextC {
                    if next == "्" || matras[next] != nil || next == " " || next == "\n" || next == "." || next == "," {
                        // Suppressed
                    } else if consonants[next] != nil || vowels[next] != nil {
                        out += "a"
                    }
                }
            } else {
                out.append(c)
            }
            i += 1
        }
        return out
    }
}
