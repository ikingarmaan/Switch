import Foundation
import Cocoa
import Carbon

public final class GlobalHotkeyService: @unchecked Sendable {
    public static let shared = GlobalHotkeyService()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    // Default hotkey: ⌘⇧Z (Command + Shift + Z)
    private let signature: OSType = OSType(1936028787) // 'SWCH'
    private let hotKeyID: UInt32 = 1
    
    private init() {}
    
    public func registerGlobalHotkey() {
        guard hotKeyRef == nil else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handlerCallback: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                theEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            
            if status == noErr && hkID.signature == OSType(1936028787) && hkID.id == 1 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("com.armank.switch.toggleAndFocusSearch"), object: nil)
                }
                return noErr
            }
            return CallNextEventHandler(nextHandler, theEvent)
        }
        
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        
        if installStatus != noErr {
            NSLog("[GlobalHotkeyService] Failed to install event handler: %d", installStatus)
            return
        }
        
        // Register ⌘⇧Z: kVK_ANSI_Z (0x06), cmdKey | shiftKey
        let hotKeyIdentifier = EventHotKeyID(signature: signature, id: hotKeyID)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Z),
            UInt32(cmdKey | shiftKey),
            hotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if regStatus == noErr {
            NSLog("[GlobalHotkeyService] Successfully registered global hotkey ⌘⇧Z (Command+Shift+Z)")
        } else {
            NSLog("[GlobalHotkeyService] Failed to register global hotkey: %d", regStatus)
        }
    }
    
    public func unregisterGlobalHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let hRef = eventHandlerRef {
            RemoveEventHandler(hRef)
            eventHandlerRef = nil
        }
    }
}

