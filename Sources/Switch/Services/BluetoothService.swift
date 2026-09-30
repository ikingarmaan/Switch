import Foundation

public final class BluetoothService: @unchecked Sendable {
    public static let shared = BluetoothService()
    
    private typealias IOBluetoothPreferenceGetControllerPowerState = @convention(c) () -> Int32
    private typealias IOBluetoothPreferenceSetControllerPowerState = @convention(c) (Int32) -> Void
    
    private var getPowerStateFunc: IOBluetoothPreferenceGetControllerPowerState?
    private var setPowerStateFunc: IOBluetoothPreferenceSetControllerPowerState?
    
    private init() {
        if let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) {
            if let getSym = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") {
                self.getPowerStateFunc = unsafeBitCast(getSym, to: IOBluetoothPreferenceGetControllerPowerState.self)
            }
            if let setSym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") {
                self.setPowerStateFunc = unsafeBitCast(setSym, to: IOBluetoothPreferenceSetControllerPowerState.self)
            }
        }
    }
    
    public func isEnabled() -> Bool {
        if let getFunc = getPowerStateFunc {
            return getFunc() == 1
        }
        // Fallback using blueutil if available
        let res = Shell.run("which blueutil && blueutil -p")
        return res.contains("1")
    }
    
    public func setEnabled(_ enabled: Bool) {
        if let setFunc = setPowerStateFunc {
            setFunc(enabled ? 1 : 0)
            return
        }
        // Fallback using blueutil if available
        _ = Shell.run("which blueutil && blueutil -p \(enabled ? 1 : 0)")
    }
}
