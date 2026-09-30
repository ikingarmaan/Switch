import Cocoa

public final class PersistenceService: @unchecked Sendable {
    public static let shared = PersistenceService()
    
    private var activityToken: NSObjectProtocol?
    private let plistLabel = "com.armank.switch"
    
    private var plistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(plistLabel).plist"
    }
    
    private init() {}
    
    @MainActor
    public func enablePersistence() {
        // 1. Prevent macOS Automatic Termination & Sudden Termination
        ProcessInfo.processInfo.disableAutomaticTermination("Switch persistent menu bar app")
        ProcessInfo.processInfo.disableSuddenTermination()
        
        // 2. Prevent App Nap / Background Throttling
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Switch background daemon"
            )
        }
        
        // 3. Clean up any legacy or rogue launchd plist to prevent duplicate daemon spawning
        removeLegacyLaunchAgent()
    }
    
    public func disablePersistence() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        removeLegacyLaunchAgent()
    }
    
    private func removeLegacyLaunchAgent() {
        let uid = getuid()
        _ = Shell.run("launchctl bootout gui/\(uid)/\(plistLabel) 2>/dev/null; launchctl unload \"\(plistPath)\" 2>/dev/null")
        try? FileManager.default.removeItem(atPath: plistPath)
    }
}
