import Foundation

public enum Shell {
    @discardableResult
    public static func run(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            var status: Int32 = 0
            waitpid(task.processIdentifier, &status, 0)
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
    
    @discardableResult
    public static func runAppleScript(_ script: String) -> (output: String, success: Bool) {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let error = error {
                let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                return (errorMsg, false)
            }
            return (output.stringValue ?? "", true)
        }
        return ("Failed to initialize AppleScript", false)
    }
}
