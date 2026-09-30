import Foundation
import IOKit.pwr_mgt

public final class KeepAwakeService: @unchecked Sendable {
    public static let shared = KeepAwakeService()
    
    private var assertionID: IOPMAssertionID = 0
    private var isAwakeActive: Bool = false
    private let lock = NSLock()
    
    private init() {}
    
    public func isEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAwakeActive
    }
    
    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        if enabled {
            guard !isAwakeActive else { return }
            let reason = "Switch App Keep Awake" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            if result == kIOReturnSuccess {
                isAwakeActive = true
            }
        } else {
            guard isAwakeActive else { return }
            let result = IOPMAssertionRelease(assertionID)
            if result == kIOReturnSuccess {
                isAwakeActive = false
                assertionID = 0
            }
        }
    }
}
