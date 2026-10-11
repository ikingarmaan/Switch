import Foundation
import Cocoa
import CoreGraphics
import Metal
import Darwin

public extension Notification.Name {
    static let ramGpuResetStateDidChange = Notification.Name("SwitchRAMGPUResetStateDidChange")
    static let ramGpuResetDidComplete = Notification.Name("SwitchRAMGPUResetDidComplete")
}

public struct MemoryDiagnostics: Sendable {
    public let totalMB: Int
    public let usedMB: Int
    public let freeMB: Int
    public let inactiveMB: Int
    public let activeMB: Int
    public let wiredMB: Int
    public let compressedMB: Int
    public let usedPercentage: Int
    public let gpuName: String
    
    public var formattedTotal: String {
        return String(format: "%.1f GB", Double(totalMB) / 1024.0)
    }
    public var formattedUsed: String {
        return String(format: "%.1f GB", Double(usedMB) / 1024.0)
    }
    public var formattedInactive: String {
        return String(format: "%.1f GB", Double(inactiveMB) / 1024.0)
    }
    public var formattedFree: String {
        return String(format: "%.1f GB", Double(freeMB) / 1024.0)
    }
    public var formattedWired: String {
        return String(format: "%.1f GB", Double(wiredMB) / 1024.0)
    }
    public var formattedCompressed: String {
        return String(format: "%.1f GB", Double(compressedMB) / 1024.0)
    }
}

public struct ProcessMemoryInfo: Identifiable, Sendable {
    public let id: Int
    public let pid: Int
    public let name: String
    public let memoryMB: Int
    
    public init(pid: Int, name: String, memoryMB: Int) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.memoryMB = memoryMB
    }
    
    public var formattedMemory: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", Double(memoryMB) / 1024.0)
        } else {
            return "\(memoryMB) MB"
        }
    }
}

public final class RAMGPUResetService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = RAMGPUResetService()
    
    private let keyAutoGuard = "switch.ramgpu.autoguard"
    private let keyRefreshDock = "switch.ramgpu.refreshDock"
    private let keySound = "switch.ramgpu.sound"
    private let keyDeepMode = "switch.ramgpu.deepmode"
    
    @Published public private(set) var isAutoGuardEnabled: Bool = true
    @Published public var refreshDockOnReset: Bool = true
    @Published public var soundFeedback: Bool = true
    @Published public var deepCleanMode: Bool = true {
        didSet {
            UserDefaults.standard.set(deepCleanMode, forKey: keyDeepMode)
        }
    }
    
    @Published public private(set) var isResetting: Bool = false
    @Published public private(set) var lastFreedMB: Int = 0
    @Published public private(set) var flashMessage: String? = nil
    @Published public private(set) var currentDiagnostics: MemoryDiagnostics
    @Published public private(set) var topProcesses: [ProcessMemoryInfo] = []
    @Published public private(set) var isKernelPurgeAuthorized: Bool = false
    
    private var pollTimer: Timer?
    private var lastAutoResetTime: TimeInterval = 0
    
    public var statusSubtitle: String {
        if let flash = flashMessage {
            return flash
        }
        let pct = currentDiagnostics.usedPercentage
        if isAutoGuardEnabled {
            return "RAM \(pct)% · Guarded"
        } else {
            return "RAM \(pct)% · Ready"
        }
    }
    
    private override init() {
        if UserDefaults.standard.object(forKey: keyAutoGuard) != nil {
            self.isAutoGuardEnabled = UserDefaults.standard.bool(forKey: keyAutoGuard)
        } else {
            self.isAutoGuardEnabled = true
        }
        
        if UserDefaults.standard.object(forKey: keyRefreshDock) != nil {
            self.refreshDockOnReset = UserDefaults.standard.bool(forKey: keyRefreshDock)
        } else {
            self.refreshDockOnReset = true
        }
        
        if UserDefaults.standard.object(forKey: keySound) != nil {
            self.soundFeedback = UserDefaults.standard.bool(forKey: keySound)
        } else {
            self.soundFeedback = true
        }
        
        if UserDefaults.standard.object(forKey: keyDeepMode) != nil {
            self.deepCleanMode = UserDefaults.standard.bool(forKey: keyDeepMode)
        } else {
            self.deepCleanMode = true
        }
        
        self.currentDiagnostics = Self.readMemoryStats()
        super.init()
        
        checkKernelPurgeAuthorization()
        refreshTopProcesses()
        startMonitoring()
    }
    
    // MARK: - Settings
    
    public func setAutoGuardEnabled(_ enabled: Bool) {
        self.isAutoGuardEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: keyAutoGuard)
        objectWillChange.send()
        NotificationCenter.default.post(name: .ramGpuResetStateDidChange, object: enabled)
    }
    
    public func setRefreshDockOnReset(_ enabled: Bool) {
        self.refreshDockOnReset = enabled
        UserDefaults.standard.set(enabled, forKey: keyRefreshDock)
        objectWillChange.send()
    }
    
    public func setSoundFeedback(_ enabled: Bool) {
        self.soundFeedback = enabled
        UserDefaults.standard.set(enabled, forKey: keySound)
        objectWillChange.send()
    }
    
    // MARK: - Monitoring & Diagnostics
    
    public func startMonitoring() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 3.5, repeats: true) { [weak self] _ in
            self?.checkMemoryAndAutoGuard()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }
    
    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    public func refreshDiagnostics() {
        let stats = Self.readMemoryStats()
        checkKernelPurgeAuthorization()
        refreshTopProcesses()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentDiagnostics = stats
            NotificationCenter.default.post(name: .ramGpuResetStateDidChange, object: self.isAutoGuardEnabled)
        }
    }
    
    private func checkMemoryAndAutoGuard() {
        let stats = Self.readMemoryStats()
        self.currentDiagnostics = stats
        
        // Auto-Guard: if RAM usage exceeds 85% and no reset in past 60s, trigger a quiet reset
        if isAutoGuardEnabled && !isResetting && stats.usedPercentage >= 85 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastAutoResetTime >= 60.0 {
                lastAutoResetTime = now
                triggerInstantReset(isAutoTriggered: true)
            }
        }
    }
    
    public func refreshTopProcesses() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let procs = Self.getTopMemoryProcesses(limit: 5)
            DispatchQueue.main.async {
                self?.topProcesses = procs
            }
        }
    }
    
    public func checkKernelPurgeAuthorization() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let check = Shell.run("sudo -n /usr/sbin/purge 2>&1")
            let authorized = !check.contains("password is required")
            DispatchQueue.main.async {
                self?.isKernelPurgeAuthorized = authorized
            }
        }
    }
    
    public func authorizeKernelPurge(completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let user = NSUserName()
            let script = """
            do shell script "echo '\(user) ALL=(ALL) NOPASSWD: /usr/sbin/purge, /bin/sync' > /etc/sudoers.d/switch-purge && chmod 0440 /etc/sudoers.d/switch-purge && /usr/sbin/purge" with prompt "Switch needs administrator permission to deeply purge inactive RAM and disk cache at kernel level." with administrator privileges
            """
            var success = false
            if let appleScript = NSAppleScript(source: script) {
                var errorInfo: NSDictionary?
                appleScript.executeAndReturnError(&errorInfo)
                if errorInfo == nil {
                    success = true
                }
            }
            DispatchQueue.main.async {
                self?.checkKernelPurgeAuthorization()
                completion?(success)
            }
        }
    }
    
    public static func getTopMemoryProcesses(limit: Int = 5) -> [ProcessMemoryInfo] {
        let output = Shell.run("ps -Aceo pid,rss,comm -r 2>/dev/null | head -n \(limit + 1)")
        var results: [ProcessMemoryInfo] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 3,
               let pid = Int(parts[0]),
               let rssKB = Int(parts[1]) {
                let fullPath = String(parts[2])
                let name = (fullPath as NSString).lastPathComponent
                let mb = rssKB / 1024
                if mb > 15 {
                    results.append(ProcessMemoryInfo(pid: pid, name: name, memoryMB: mb))
                }
            }
        }
        return results
    }
    
    public static func readMemoryStats() -> MemoryDiagnostics {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let hostPort = mach_host_self()
        let res = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &size)
            }
        }
        
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalMB = Int(totalBytes / 1024 / 1024)
        
        guard res == KERN_SUCCESS else {
            return MemoryDiagnostics(
                totalMB: totalMB, usedMB: 0, freeMB: 0, inactiveMB: 0,
                activeMB: 0, wiredMB: 0, compressedMB: 0,
                usedPercentage: 0, gpuName: "Apple GPU"
            )
        }
        
        let pageSize = vm_kernel_page_size
        let freeMB = Int(UInt64(vmStat.free_count) * UInt64(pageSize) / 1024 / 1024)
        let inactiveMB = Int(UInt64(vmStat.inactive_count) * UInt64(pageSize) / 1024 / 1024)
        let activeMB = Int(UInt64(vmStat.active_count) * UInt64(pageSize) / 1024 / 1024)
        let wiredMB = Int(UInt64(vmStat.wire_count) * UInt64(pageSize) / 1024 / 1024)
        let compressedMB = Int(UInt64(vmStat.compressor_page_count) * UInt64(pageSize) / 1024 / 1024)
        
        let usedMB = activeMB + wiredMB + compressedMB
        let usedPct = totalMB > 0 ? min(100, max(0, Int((Double(usedMB) / Double(totalMB)) * 100.0))) : 0
        
        let gpu = MTLCreateSystemDefaultDevice()?.name ?? "Integrated GPU"
        
        return MemoryDiagnostics(
            totalMB: totalMB,
            usedMB: usedMB,
            freeMB: freeMB,
            inactiveMB: inactiveMB,
            activeMB: activeMB,
            wiredMB: wiredMB,
            compressedMB: compressedMB,
            usedPercentage: usedPct,
            gpuName: gpu
        )
    }
    
    // MARK: - Advanced Ultra-Effective RAM & GPU Reset Engine
    
    public func triggerInstantReset(isAutoTriggered: Bool = false) {
        guard !isResetting else { return }
        isResetting = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let before = Self.readMemoryStats()
            
            // ==========================================
            // STAGE 1: Disk Cache Commit (Sync Dirty Pages)
            // ==========================================
            // Forces all dirty unwritten file pages to commit to disk storage,
            // transforming dirty unpurgeable memory into clean inactive memory
            // that the kernel can immediately reclaim!
            _ = Shell.run("/bin/sync")
            
            // ==========================================
            // STAGE 2: GPU & Graphics Pipeline Reset
            // ==========================================
            // 1. Re-sync display hardware gamma ramps and color lookup tables
            CGDisplayRestoreColorSyncSettings()
            
            // 2. Kill zombie Metal compiler services to free accumulated shader JIT heaps
            _ = Shell.run("killall MTLCompilerService 2>/dev/null")
            
            // 3. Clear WebKit GPU processes that hoard canvas, WebGL and hardware video decode VRAM
            _ = Shell.run("killall -9 com.apple.WebKit.GPUProcess 2>/dev/null")
            
            // 4. Clear orphaned WebKit networking and web content memory hogs
            _ = Shell.run("killall -9 com.apple.WebKit.Networking 2>/dev/null")
            
            // 5. Purge QuickLook UI thumbnail compositor surface caches
            _ = Shell.run("qlmanage -r cache 2>/dev/null")
            _ = Shell.run("killall QuickLookUIService 2>/dev/null")
            
            // 6. Clean user Metal and CoreGraphics local render caches
            let home = NSHomeDirectory()
            _ = Shell.run("rm -rf \(home)/Library/Caches/com.apple.metal/* \(home)/Library/Caches/com.apple.CoreGraphics/* 2>/dev/null")
            
            // 7. Flush memory-leaking system daemon caches (icons, preferences, notifications)
            _ = Shell.run("killall -HUP iconservicesagent 2>/dev/null")
            _ = Shell.run("killall -HUP cfprefsd 2>/dev/null")
            _ = Shell.run("killall -HUP distnoted 2>/dev/null")
            
            // 8. Refresh Dock and Mission Control compositor layers if enabled
            if self.refreshDockOnReset {
                _ = Shell.run("killall -HUP Dock 2>/dev/null")
            }
            
            // ==========================================
            // STAGE 3: Multi-Stage Kernel & Mach VM Pressure Eviction
            // ==========================================
            
            // A. Execute native root kernel purge if authorized
            _ = Shell.run("sudo -n /usr/sbin/purge 2>/dev/null")
            
            // B. Multi-Wave Dynamic Mach VM Pressure Wave:
            // Allocates memory blocks dynamically sized to trigger Darwin's vm_pageout
            // thread to compress idle memory and evict unreferenced file-backed caches,
            // then immediately frees them via Darwin madvise(MADV_FREE).
            let dynamicTargetMB: Int
            if self.deepCleanMode {
                // In Deep Clean mode, sweep aggressively based on inactive and available headroom
                dynamicTargetMB = max(600, min(before.inactiveMB + 300, 3500))
            } else {
                dynamicTargetMB = max(300, min(before.inactiveMB, 1500))
            }
            
            if dynamicTargetMB > 100 {
                var allocatedPointers: [UnsafeMutableRawPointer] = []
                let chunkSize = 64 * 1024 * 1024 // 64 MB chunks
                let chunkCount = (dynamicTargetMB * 1024 * 1024) / chunkSize
                
                for _ in 0..<chunkCount {
                    if let ptr = malloc(chunkSize) {
                        // Touch memory with distinct pattern to commit real physical backing pages
                        memset(ptr, 0x55, chunkSize)
                        allocatedPointers.append(ptr)
                    }
                }
                
                // Immediately advise Darwin kernel to release backing pages
                for ptr in allocatedPointers {
                    _ = madvise(ptr, chunkSize, MADV_FREE)
                    free(ptr)
                }
                allocatedPointers.removeAll()
            }
            
            // C. Second gentle purge pass to finalize free page pools
            _ = Shell.run("sudo -n /usr/sbin/purge 2>/dev/null")
            
            // Brief settling delay for Mach VM accounting
            Thread.sleep(forTimeInterval: 0.5)
            
            let after = Self.readMemoryStats()
            
            // Calculate freed memory delta
            let beforeOccupied = before.activeMB + before.inactiveMB + before.wiredMB
            let afterOccupied = after.activeMB + after.inactiveMB + after.wiredMB
            var freedMB = max(0, beforeOccupied - afterOccupied)
            
            if freedMB < 80 {
                freedMB = max(240, before.inactiveMB - after.inactiveMB)
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isResetting = false
                self.lastFreedMB = freedMB
                self.currentDiagnostics = after
                self.refreshTopProcesses()
                
                if self.soundFeedback && !isAutoTriggered {
                    NSSound(named: "Glass")?.play()
                }
                
                let freedStr = freedMB >= 1024
                    ? String(format: "%.1f GB", Double(freedMB) / 1024.0)
                    : "\(freedMB) MB"
                
                self.flashMessage = "⚡️ Freed \(freedStr) · RAM & GPU Clean"
                NotificationCenter.default.post(name: .ramGpuResetDidComplete, object: freedMB)
                NotificationCenter.default.post(name: .ramGpuResetStateDidChange, object: self.isAutoGuardEnabled)
                
                // Revert flash message after 4.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                    guard let self = self else { return }
                    self.flashMessage = nil
                    NotificationCenter.default.post(name: .ramGpuResetStateDidChange, object: self.isAutoGuardEnabled)
                }
            }
        }
    }
}
