import Foundation
import Cocoa
import SwiftUI

public extension Notification.Name {
    static let nightShiftDidChange = Notification.Name("SwitchNightShiftDidChange")
}

@objc private protocol BlueLightProtocol: NSObjectProtocol {
    func setEnabled(_ enabled: Bool) -> Bool
    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    static func supportsBlueLightReduction() -> Bool
    func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
    func setStrength(_ strength: Float, commit: Bool) -> Bool
    func setStatusNotificationBlock(_ block: @escaping @convention(block) () -> Void)
}

public final class NightShiftService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = NightShiftService()
    
    private var client: AnyObject?
    private var isSupported: Bool = false
    
    @Published public var currentStrength: Float = 0.5
    
    public let presets: [(strength: Float, label: String)] = [
        (0.25, "Subtle (25%)"),
        (0.50, "Balanced (50%)"),
        (0.75, "Warm (75%)"),
        (1.00, "Max Warmth (100%)")
    ]
    
    private let keyStrength = "switch_night_shift_strength"
    
    override private init() {
        super.init()
        
        if let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) {
            _ = handle
            if let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
                let clientInstance = clientClass.init()
                self.client = clientInstance
                self.isSupported = true
                
                // Read hardware/system strength
                let typedClient = unsafeBitCast(clientInstance, to: BlueLightProtocol.self)
                var s: Float = 0.0
                if typedClient.getStrength(&s) && s > 0 {
                    self.currentStrength = s
                } else {
                    let saved = UserDefaults.standard.float(forKey: keyStrength)
                    self.currentStrength = saved > 0 ? saved : 0.5
                }
                
                // Set status notification block
                typedClient.setStatusNotificationBlock { [weak self] in
                    DispatchQueue.main.async {
                        self?.syncFromSystem()
                    }
                }
                return
            }
        }
        
        let saved = UserDefaults.standard.float(forKey: keyStrength)
        self.currentStrength = saved > 0 ? saved : 0.5
    }
    
    public var formattedStrength: String {
        return "\(Int(round(currentStrength * 100)))%"
    }
    
    public var strengthLabel: String {
        if currentStrength <= 0.35 {
            return "Subtle"
        } else if currentStrength <= 0.65 {
            return "Balanced"
        } else if currentStrength <= 0.85 {
            return "Warm"
        } else {
            return "Max"
        }
    }
    
    public var subtitle: String {
        if isEnabled() {
            return "\(strengthLabel) • \(formattedStrength)"
        } else {
            return formattedStrength
        }
    }
    
    public func isAvailable() -> Bool {
        return isSupported
    }
    
    public func isEnabled() -> Bool {
        guard let client = client else { return false }
        let typedClient = unsafeBitCast(client, to: BlueLightProtocol.self)
        var statusData = [UInt8](repeating: 0, count: 64)
        if typedClient.getBlueLightStatus(&statusData) {
            // Byte 1 indicates `enabled` in macOS BlueLightStatus struct
            return statusData[1] == 1
        }
        return false
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard let client = client else { return }
        let typedClient = unsafeBitCast(client, to: BlueLightProtocol.self)
        _ = typedClient.setEnabled(enabled)
        if enabled {
            _ = typedClient.setStrength(currentStrength, commit: true)
        }
        notifyChange()
    }
    
    public func setStrength(_ strength: Float) {
        let clamped = max(0.0, min(1.0, strength))
        self.currentStrength = clamped
        UserDefaults.standard.set(clamped, forKey: keyStrength)
        
        if let client = client {
            let typedClient = unsafeBitCast(client, to: BlueLightProtocol.self)
            _ = typedClient.setStrength(clamped, commit: true)
        }
        
        notifyChange()
    }
    
    public func syncFromSystem() {
        guard let client = client else { return }
        let typedClient = unsafeBitCast(client, to: BlueLightProtocol.self)
        var s: Float = 0.0
        if typedClient.getStrength(&s) && s > 0 {
            self.currentStrength = s
            UserDefaults.standard.set(s, forKey: keyStrength)
        }
        notifyChange()
    }
    
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .nightShiftDidChange, object: self.currentStrength)
        }
    }
}
