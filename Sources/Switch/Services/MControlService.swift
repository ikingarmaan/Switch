import Cocoa
import Foundation
import Combine

public extension Notification.Name {
    static let mControlStateDidChange = Notification.Name("SwitchMControlStateDidChange")
}

public final class MControlService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = MControlService()
    
    private let keyAutoStart = "Switch_MControl_AutoStart"
    private let keyCustomPath = "Switch_MControl_CustomPath"
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var localIP: String = "127.0.0.1"
    @Published public private(set) var serverPort: Int = 8000
    
    private var process: Process?
    private var statusTimer: Timer?
    
    public static let primaryPath = "/Users/ikingarmaan/.gemini/antigravity/scratch/mac-remote-control"
    public static let fallbackPath = "\(NSHomeDirectory())/Desktop/mac-remote-control"
    
    public var activeDirectoryPath: String {
        let saved = UserDefaults.standard.string(forKey: keyCustomPath) ?? ""
        if !saved.isEmpty && FileManager.default.fileExists(atPath: saved) {
            return saved
        }
        if FileManager.default.fileExists(atPath: Self.primaryPath) {
            return Self.primaryPath
        }
        if FileManager.default.fileExists(atPath: Self.fallbackPath) {
            return Self.fallbackPath
        }
        return Self.primaryPath
    }
    
    public var remoteURLString: String {
        return "http://\(localIP):\(serverPort)"
    }
    
    public var statusSubtitle: String {
        if isRunning {
            return "🟢 Online · \(localIP):\(serverPort)"
        } else {
            return "Offline"
        }
    }
    
    private override init() {
        super.init()
        updateLocalIP()
        checkStatus()
        
        statusTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }
    
    deinit {
        statusTimer?.invalidate()
    }
    
    // MARK: - IP & Status Resolution
    
    public func updateLocalIP() {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let flags = Int32(ptr!.pointee.ifa_flags)
                var addr = ptr!.pointee.ifa_addr.pointee
                
                // Check for IPv4 and non-loopback
                if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                    if addr.sa_family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                            let name = String(cString: ptr!.pointee.ifa_name)
                            if name.hasPrefix("en") { // Wi-Fi / Ethernet interface
                                address = String(cString: hostname)
                                break
                            }
                        }
                    }
                }
                ptr = ptr!.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        
        DispatchQueue.main.async {
            self.localIP = address
        }
    }
    
    @discardableResult
    public func checkStatus() -> Bool {
        // Check if server is listening on port 8000
        let portCheck = Shell.run("lsof -ti :\(serverPort) 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        let active = !portCheck.isEmpty || (process != nil && process!.isRunning)
        
        if active != isRunning {
            DispatchQueue.main.async {
                self.isRunning = active
                NotificationCenter.default.post(name: .mControlStateDidChange, object: active)
            }
        }
        return active
    }
    
    // MARK: - Control Actions
    
    public func toggle() {
        if isRunning {
            stopServer()
        } else {
            startServer()
        }
    }
    
    public func startServer() {
        updateLocalIP()
        let dir = activeDirectoryPath
        guard FileManager.default.fileExists(atPath: dir) else {
            print("MControl Error: Directory not found at \(dir)")
            return
        }
        
        // Kill any existing stale process on port 8000 first
        _ = Shell.run("lsof -ti :\(serverPort) | xargs kill -9 2>/dev/null || true")
        
        let startScript = "\(dir)/start.sh"
        let proc = Process()
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        
        if FileManager.default.isExecutableFile(atPath: startScript) {
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [startScript]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = ["-c", "cd '\(dir)' && python3 server.py"]
        }
        
        // Direct output to log
        let logDir = "\(NSHomeDirectory())/Library/Application Support/Switch"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logPath = "\(logDir)/mcontrol.log"
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            proc.standardOutput = fileHandle
            proc.standardError = fileHandle
        }
        
        do {
            try proc.run()
            self.process = proc
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.checkStatus()
            }
        } catch {
            print("MControl failed to start: \(error)")
            // Fallback: spawn in detached background shell
            _ = Shell.run("nohup /bin/bash -c 'cd \"\(dir)\" && ./start.sh' > '\(logPath)' 2>&1 &")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.checkStatus()
            }
        }
    }
    
    public func stopServer() {
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        
        // Cleanly terminate any remaining server.py on port 8000
        _ = Shell.run("lsof -ti :\(serverPort) | xargs kill -9 2>/dev/null || true")
        _ = Shell.run("pkill -f 'server.py' 2>/dev/null || true")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.checkStatus()
        }
    }
    
    public func restartServer() {
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServer()
        }
    }
    
    public func openInBrowser() {
        if let url = URL(string: remoteURLString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func copyRemoteURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(remoteURLString, forType: .string)
    }
    
    public func openProjectFolder() {
        let dir = activeDirectoryPath
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir)
    }
}
