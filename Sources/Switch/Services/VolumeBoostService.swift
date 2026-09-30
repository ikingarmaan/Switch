import Foundation
import CoreAudio
import AudioToolbox
import AppKit

public extension Notification.Name {
    static let volumeBoostStateDidChange = Notification.Name("SwitchVolumeBoostStateDidChange")
}

/// Volume boost levels matching FineTune: 1x (Unity/Off), 2x (+6dB), 3x (+9.5dB), 4x (+12dB)
public enum VolumeBoostLevel: Float, CaseIterable, Identifiable, Sendable {
    case x1 = 1.0
    case x2 = 2.0
    case x3 = 3.0
    case x4 = 4.0
    
    public var id: Float { rawValue }
    public var multiplier: Float { rawValue }
    
    public var label: String {
        switch self {
        case .x1: return "Off"
        case .x2: return "2x"
        case .x3: return "3x"
        case .x4: return "4x"
        }
    }
    
    public var displayTitle: String {
        switch self {
        case .x1: return "1x (Normal)"
        case .x2: return "Level 1 (2x · +6 dB)"
        case .x3: return "Level 2 (3x · +9.5 dB)"
        case .x4: return "Level 3 (4x · +12 dB)"
        }
    }
    
    public var litChevronsCount: Int {
        switch self {
        case .x1: return 0
        case .x2: return 1
        case .x3: return 2
        case .x4: return 3
        }
    }
    
    public var nextLevel: VolumeBoostLevel {
        switch self {
        case .x1: return .x2
        case .x2: return .x3
        case .x3: return .x4
        case .x4: return .x1
        }
    }
    
    public static var activePresets: [VolumeBoostLevel] {
        return [.x2, .x3, .x4]
    }
}

/// RT-safe soft-knee limiter using asymptotic compression (matching FineTune).
/// Prevents harsh digital clipping distortion when audio is amplified above unity gain.
enum SoftLimiter {
    static let threshold: Float = 0.95
    static let ceiling: Float = 1.0
    static let headroom: Float = 0.05
    
    @inline(__always)
    static func apply(_ sample: Float) -> Float {
        let absSample = abs(sample)
        if absSample <= threshold {
            return sample
        }
        let overshoot = absSample - threshold
        let compressed = threshold + headroom * (overshoot / (overshoot + headroom))
        return sample >= 0 ? compressed : -compressed
    }
}

public final class VolumeBoostService: ObservableObject, @unchecked Sendable {
    public static let shared = VolumeBoostService()
    
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var selectedLevel: VolumeBoostLevel = .x2
    
    public var activeLevel: VolumeBoostLevel {
        isActive ? selectedLevel : .x1
    }
    
    // CoreAudio resources
    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID? = nil
    
    // Non-isolated realtime gain multiplier accessed by audio callback thread
    private nonisolated(unsafe) var currentGain: Float = 2.0
    
    private let audioQueue = DispatchQueue(label: "com.armank.switch.volumeBoostQueue", qos: .userInitiated)
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?
    private var pendingActivation: Bool = false
    private var savedSystemVolume: Int? = nil
    
    private init() {
        // Safe teardown on app termination
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        
        // Auto-activate if user toggled permission in System Settings and returned to Switch
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.isActive && self.pendingActivation && Self.isAudioCaptureAuthorized {
                NSLog("[VolumeBoostService] Permission now granted on app activation! Starting volume boost...")
                self.pendingActivation = false
                self.start(level: self.selectedLevel)
            }
        }
        
        setupDeviceChangeListener()
        setupDistributedNotificationListeners()
    }
    
    deinit {
        stop()
    }
    
    private func setupDistributedNotificationListeners() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.volumeBoost.toggle"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggle()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.volumeBoost.start"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.start()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.volumeBoost.stop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.volumeBoost.setLevel"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self, let levelStr = notif.object as? String else { return }
            if let level = VolumeBoostLevel.allCases.first(where: { $0.label.lowercased() == levelStr.lowercased() }) {
                self.setLevel(level)
            }
        }
    }
    
    // MARK: - Permission Management
    
    public static var isAudioCaptureAuthorized: Bool {
        if let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_LAZY) {
            defer { dlclose(handle) }
            typealias PreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
            if let sym = dlsym(handle, "TCCAccessPreflight") {
                let preflight = unsafeBitCast(sym, to: PreflightFunc.self)
                let status = preflight("kTCCServiceScreenCapture" as CFString, nil)
                return status == 0
            }
        }
        if #available(macOS 11.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }
    
    public static func requestPermission() {
        if #available(macOS 11.0, *) {
            _ = CGRequestScreenCaptureAccess()
        }
    }
    
    public static func openSystemSettingsPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func promptPermissionRequired() {
        DispatchQueue.main.async {
            Self.requestPermission()
            Self.openSystemSettingsPrivacy()
            
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Enable Switch for Volume Boost"
            alert.informativeText = "macOS requires \"Screen & System Audio Recording\" permission to amplify volume up to 4x (matching FineTune).\n\n1. In the System Settings window that just opened, turn the toggle next to \"Switch\" ON.\n2. Return to Switch and Volume Boost will activate automatically."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            
            if alert.runModal() == .alertFirstButtonReturn {
                Self.openSystemSettingsPrivacy()
            }
        }
    }
    
    // MARK: - User Controls
    
    public func toggle() {
        if isActive {
            stop()
        } else {
            start(level: selectedLevel == .x1 ? .x2 : selectedLevel)
        }
    }
    
    public func setLevel(_ level: VolumeBoostLevel) {
        selectedLevel = level
        currentGain = level.multiplier
        if !isActive && level != .x1 {
            start(level: level)
        } else if isActive && level == .x1 {
            stop()
        } else if isActive {
            playFeedbackSound()
            NotificationCenter.default.post(name: .volumeBoostStateDidChange, object: isActive)
        }
    }
    
    public func cycleLevel() {
        let next = selectedLevel.nextLevel
        if next == .x1 {
            stop()
            selectedLevel = .x2
        } else {
            setLevel(next)
        }
    }
    
    public func start(level: VolumeBoostLevel? = nil) {
        NSLog("[VolumeBoostService] start() called with level: %@", level?.label ?? "default")
        
        let targetLevel = level ?? selectedLevel
        selectedLevel = targetLevel == .x1 ? .x2 : targetLevel
        currentGain = selectedLevel.multiplier
        
        guard Self.isAudioCaptureAuthorized else {
            NSLog("[VolumeBoostService] ScreenCapture not authorized. Requesting and prompting user...")
            pendingActivation = true
            isActive = false
            NotificationCenter.default.post(name: .volumeBoostStateDidChange, object: false)
            promptPermissionRequired()
            return
        }
        
        pendingActivation = false
        stopAudioEngine()
        
        // Ensure max volume headroom
        bumpSystemVolumeIfNeeded()
        
        do {
            try startAudioEngine()
            isActive = true
            NotificationCenter.default.post(name: .volumeBoostStateDidChange, object: true)
            playFeedbackSound()
            NSLog("[VolumeBoostService] Volume boost is now ACTIVE at %@ (gain: %f)", selectedLevel.label, currentGain)
        } catch {
            NSLog("[VolumeBoostService] Failed to start volume boost: %@", error.localizedDescription)
            stopAudioEngine()
            isActive = false
            NotificationCenter.default.post(name: .volumeBoostStateDidChange, object: false)
            promptPermissionRequired()
        }
    }
    
    public func stop() {
        pendingActivation = false
        stopAudioEngine()
        restoreSystemVolumeIfNeeded()
        isActive = false
        NotificationCenter.default.post(name: .volumeBoostStateDidChange, object: false)
    }
    
    private func bumpSystemVolumeIfNeeded() {
        let volStr = Shell.run("osascript -e 'output volume of (get volume settings)'")
        if let vol = Int(volStr.trimmingCharacters(in: .whitespacesAndNewlines)), vol < 100 {
            if savedSystemVolume == nil {
                savedSystemVolume = vol
            }
            _ = Shell.run("osascript -e 'set volume output volume 100'")
        }
    }
    
    private func restoreSystemVolumeIfNeeded() {
        if let saved = savedSystemVolume {
            _ = Shell.run("osascript -e 'set volume output volume \(saved)'")
            savedSystemVolume = nil
        }
    }
    
    private func playFeedbackSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            let soundPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
            if let sound = NSSound(contentsOfFile: soundPath, byReference: true) ?? NSSound(named: "Tink") {
                sound.volume = 1.0
                sound.play()
            }
        }
    }
    
    // MARK: - Core Audio Engine
    
    private func getDefaultOutputDeviceUID() -> String? {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        
        guard status == noErr, defaultOutputDeviceID != kAudioObjectUnknown else {
            return nil
        }
        
        var deviceUID: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let uidStatus = withUnsafeMutablePointer(to: &deviceUID) { ptr in
            AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &uidAddress,
                0,
                nil,
                &uidSize,
                ptr
            )
        }
        
        guard uidStatus == noErr else { return nil }
        return deviceUID as String
    }
    
    private static func isDeviceAlive(_ deviceID: AudioObjectID) -> Bool {
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
        return status == noErr && alive != 0
    }
    
    private func startAudioEngine() throws {
        guard #available(macOS 14.2, *) else {
            throw NSError(domain: "VolumeBoostService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Volume boost requires macOS 14.2 or newer"])
        }
        
        guard let outputUID = getDefaultOutputDeviceUID(), !outputUID.isEmpty else {
            throw NSError(domain: "VolumeBoostService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No default output device"])
        }
        
        // 1. Determine own AudioObjectID so we exclude ourselves from the tap to prevent feedback loops
        let myPID = ProcessInfo.processInfo.processIdentifier
        var ownAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ownObjectID = AudioObjectID(kAudioObjectUnknown)
        var ownSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var myPIDCopy = myPID
        let ownStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &ownAddress,
            UInt32(MemoryLayout<pid_t>.size),
            &myPIDCopy,
            &ownSize,
            &ownObjectID
        )
        
        let excludeList: [AudioObjectID] = (ownStatus == noErr && ownObjectID != kAudioObjectUnknown) ? [ownObjectID] : []
        
        // 2. Create stereo global tap of all processes except Switch itself
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: excludeList)
        let tapUUID = UUID()
        tapDesc.uuid = tapUUID
        tapDesc.muteBehavior = .mutedWhenTapped
        tapDesc.isPrivate = true
        
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapErr = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapErr == noErr else {
            NSLog("[VolumeBoostService] AudioHardwareCreateProcessTap failed: %d", tapErr)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(tapErr), userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateProcessTap failed: \(tapErr)"])
        }
        self.tapID = newTapID
        NSLog("[VolumeBoostService] Created Process Tap ID: %u", newTapID)
        
        // 3. Create aggregate device that routes tapped audio to default output with drift compensation
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Switch-VolumeBoost",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: false
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString
                ]
            ]
        ]
        
        var newAggID = AudioObjectID(kAudioObjectUnknown)
        let aggErr = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &newAggID)
        guard aggErr == noErr else {
            NSLog("[VolumeBoostService] AudioHardwareCreateAggregateDevice failed: %d", aggErr)
            AudioHardwareDestroyProcessTap(self.tapID)
            self.tapID = AudioObjectID(kAudioObjectUnknown)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(aggErr), userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateAggregateDevice failed: \(aggErr)"])
        }
        self.aggregateDeviceID = newAggID
        NSLog("[VolumeBoostService] Created Aggregate Device ID: %u for output: %@", newAggID, outputUID)
        
        // Wait up to 2.0s for the aggregate device to become alive in CoreAudio HAL
        let waitStart = CFAbsoluteTimeGetCurrent()
        while !Self.isDeviceAlive(self.aggregateDeviceID) && (CFAbsoluteTimeGetCurrent() - waitStart) < 2.0 {
            _ = CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        
        // 4. Create IOProc on the dedicated audio queue that applies boost gain + SoftLimiter
        var newProcID: AudioDeviceIOProcID? = nil
        let procErr = AudioDeviceCreateIOProcIDWithBlock(&newProcID, self.aggregateDeviceID, audioQueue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self = self else {
                let outputs = UnsafeMutableAudioBufferListPointer(outOutputData)
                for buf in outputs {
                    if let data = buf.mData { memset(data, 0, Int(buf.mDataByteSize)) }
                }
                return
            }
            
            let gain = self.currentGain
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)
            
            let inputCount = inputBuffers.count
            let outputCount = outputBuffers.count
            
            guard inputCount > 0, outputCount > 0 else { return }
            
            for outputIndex in 0..<outputCount {
                let outputBuffer = outputBuffers[outputIndex]
                guard let outputData = outputBuffer.mData else { continue }
                
                let inputIndex = inputCount > outputCount
                    ? inputCount - outputCount + outputIndex
                    : outputIndex
                
                guard inputIndex < inputCount,
                      let inputBuffer = inputBuffers[inputIndex].mData else {
                    memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                    continue
                }
                
                let inSamples = inputBuffer.assumingMemoryBound(to: Float.self)
                let outSamples = outputData.assumingMemoryBound(to: Float.self)
                let sampleCount = min(Int(inputBuffers[inputIndex].mDataByteSize), Int(outputBuffer.mDataByteSize)) / MemoryLayout<Float>.size
                
                for s in 0..<sampleCount {
                    let boosted = inSamples[s] * gain
                    outSamples[s] = SoftLimiter.apply(boosted)
                }
                
                let processedBytes = sampleCount * MemoryLayout<Float>.size
                if processedBytes < Int(outputBuffer.mDataByteSize) {
                    let remainingBytes = Int(outputBuffer.mDataByteSize) - processedBytes
                    memset(outputData.advanced(by: processedBytes), 0, remainingBytes)
                }
            }
        }
        
        guard procErr == noErr, let validProcID = newProcID else {
            NSLog("[VolumeBoostService] AudioDeviceCreateIOProcIDWithBlock failed: %d", procErr)
            AudioHardwareDestroyAggregateDevice(self.aggregateDeviceID)
            self.aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            AudioHardwareDestroyProcessTap(self.tapID)
            self.tapID = AudioObjectID(kAudioObjectUnknown)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(procErr), userInfo: [NSLocalizedDescriptionKey: "AudioDeviceCreateIOProcIDWithBlock failed: \(procErr)"])
        }
        self.deviceProcID = validProcID
        
        // 5. Start audio output
        let startErr = AudioDeviceStart(self.aggregateDeviceID, validProcID)
        guard startErr == noErr else {
            NSLog("[VolumeBoostService] AudioDeviceStart failed: %d", startErr)
            AudioDeviceDestroyIOProcID(self.aggregateDeviceID, validProcID)
            self.deviceProcID = nil
            AudioHardwareDestroyAggregateDevice(self.aggregateDeviceID)
            self.aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            AudioHardwareDestroyProcessTap(self.tapID)
            self.tapID = AudioObjectID(kAudioObjectUnknown)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(startErr), userInfo: [NSLocalizedDescriptionKey: "AudioDeviceStart failed: \(startErr)"])
        }
        NSLog("[VolumeBoostService] AudioDeviceStart succeeded! Amplifying audio at %fx", self.currentGain)
    }
    
    private func stopAudioEngine() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            if let procID = deviceProcID {
                _ = AudioDeviceStop(aggregateDeviceID, procID)
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                deviceProcID = nil
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        
        if #available(macOS 14.2, *) {
            if tapID != AudioObjectID(kAudioObjectUnknown) {
                _ = AudioHardwareDestroyProcessTap(tapID)
                tapID = AudioObjectID(kAudioObjectUnknown)
            }
        }
    }
    
    // MARK: - Device Change Listener
    
    private func setupDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isActive else { return }
                print("[VolumeBoostService] Default output device changed, restarting tap...")
                self.start(level: self.selectedLevel)
            }
        }
        self.deviceChangeListenerBlock = block
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }
}
