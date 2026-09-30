import Foundation
import CoreAudio
import AudioToolbox

public final class AudioService: @unchecked Sendable {
    public static let shared = AudioService()
    
    private init() {}
    
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
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
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID
        )
        
        guard status == noErr, defaultOutputDeviceID != kAudioObjectUnknown else {
            return kAudioObjectUnknown
        }
        return defaultOutputDeviceID
    }
    
    public func isMuted() -> Bool {
        let deviceID = getDefaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else {
            // Fallback to AppleScript
            let result = Shell.run("osascript -e 'output muted of (get volume settings)'")
            return result.lowercased() == "true"
        }
        
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var mutedValue: UInt32 = 0
        var mutedSize = UInt32(MemoryLayout.size(ofValue: mutedValue))
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            &mutedSize,
            &mutedValue
        )
        
        if status == noErr {
            return mutedValue == 1
        }
        
        // Fallback
        let result = Shell.run("osascript -e 'output muted of (get volume settings)'")
        return result.lowercased() == "true"
    }
    
    public func setMuted(_ muted: Bool) {
        let deviceID = getDefaultOutputDevice()
        if deviceID != kAudioObjectUnknown {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var canSetMute: DarwinBoolean = false
            let settableStatus = AudioObjectIsPropertySettable(deviceID, &muteAddress, &canSetMute)
            
            if settableStatus == noErr && canSetMute.boolValue {
                var mutedValue: UInt32 = muted ? 1 : 0
                let size = UInt32(MemoryLayout.size(ofValue: mutedValue))
                let status = AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &mutedValue)
                if status == noErr {
                    return
                }
            }
        }
        
        // Fallback to AppleScript
        _ = Shell.run("osascript -e 'set volume output muted \(muted)'")
    }
}
