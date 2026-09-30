import Cocoa

@main
struct SwitchMain {
    static func main() {
        let bundleID = "com.armank.switch"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let myPID = ProcessInfo.processInfo.processIdentifier
        
        if runningApps.contains(where: { $0.processIdentifier != myPID }) {
            exit(0)
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
