import Foundation

@objc private protocol BlueLightProtocol: NSObjectProtocol {
    func setEnabled(_ enabled: Bool) -> Bool
    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    static func supportsBlueLightReduction() -> Bool
}

public final class NightShiftService: @unchecked Sendable {
    public static let shared = NightShiftService()
    
    private var client: AnyObject?
    private var isSupported: Bool = false
    
    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) {
            _ = handle
            if let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
                self.client = clientClass.init()
                self.isSupported = true
            }
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
    }
}
