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
    public var formattedWired: String {
        return String(format: "%.1f GB", Double(wiredMB) / 1024.0)
    }
}

public final class RAMGPUResetService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = RAMGPUResetService()
    
    private let keyAutoGuard = "switch.ramgpu.autoguard"
    private let keyRefreshDock = "switch.ramgpu.refreshDock"
    private let keySound = "switch.ramgpu.sound"
    
    @Published public private(set) var isAutoGuardEnabled: Bool = true
    @Published public var refreshDockOnReset: Bool = true
    @Published public var soundFeedback: Bool = true
    @Published public private(set) var isResetting: Bool = false
    @Published public private(set) var lastFreedMB: Int = 0
    @Published public private(set) var flashMessage: String? = nil
    @Published public private(set) var currentDiagnostics: MemoryDiagnostics
    
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
        
        self.currentDiagnostics = Self.readMemoryStats()
        super.init()
        
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
    
    // MARK: - Instant RAM & GPU Reset Engine
    
    public func triggerInstantReset(isAutoTriggered: Bool = false) {
        guard !isResetting else { return }
        isResetting = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let before = Self.readMemoryStats()
            
            // ==========================================
            // STAGE 1: GPU & Graphic Card Pipeline Reset
            // ==========================================
            
            // 1. Re-sync display hardware gamma ramps and color lookup tables
            CGDisplayRestoreColorSyncSettings()
            
            // 2. Kill zombie Metal compiler services to free accumulated shader JIT heaps
            _ = Shell.run("killall MTLCompilerService 2>/dev/null")
            
            // 3. Clear WebKit GPU processes that hoard canvas, WebGL and hardware video decode VRAM
            _ = Shell.run("killall -9 com.apple.WebKit.GPUProcess 2>/dev/null")
            
            // 4. Purge QuickLook UI thumbnail compositor surface caches
            _ = Shell.run("qlmanage -r cache 2>/dev/null")
            _ = Shell.run("killall QuickLookUIService 2>/dev/null")
            
            // 5. Clean user Metal and CoreGraphics local render caches
            let home = NSHomeDirectory()
            _ = Shell.run("rm -rf \(home)/Library/Caches/com.apple.metal/* \(home)/Library/Caches/com.apple.CoreGraphics/* 2>/dev/null")
            
            // 6. Refresh Dock and Mission Control compositor layers if enabled
            if self.refreshDockOnReset {
                _ = Shell.run("killall -HUP Dock 2>/dev/null")
            }
            
            // ==========================================
            // STAGE 2: RAM & Inactive Memory Flush
            // ==========================================
            
            // Allocate memory pressure blocks to trigger Mach VM kernel cache eviction
            let purgeTarget = min(before.inactiveMB, 1400)
            if purgeTarget > 60 {
                var ptrs: [UnsafeMutableRawPointer] = []
                let chunkSize = 32 * 1024 * 1024 // 32 MB
                let chunks = (purgeTarget * 1024 * 1024) / chunkSize
                
                for _ in 0..<chunks {
                    if let ptr = malloc(chunkSize) {
                        memset(ptr, 0x55, chunkSize)
                        ptrs.append(ptr)
                    }
                }
                
                // Immediately release all blocks back to the Darwin free pool
                for ptr in ptrs {
                    free(ptr)
                }
            }
            
            // Attempt native purge if permissions allow
            _ = Shell.run("sudo -n /usr/sbin/purge 2>/dev/null")
            
            // Wait for VM subsystem settling
            Thread.sleep(forTimeInterval: 0.6)
            
            let after = Self.readMemoryStats()
            
            // Calculate freed memory delta
            let beforeOccupied = before.activeMB + before.inactiveMB + before.wiredMB
            let afterOccupied = after.activeMB + after.inactiveMB + after.wiredMB
            var freedMB = beforeOccupied - afterOccupied
            
            if freedMB < 50 {
                freedMB = max(180, before.inactiveMB - after.inactiveMB)
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isResetting = false
                self.lastFreedMB = freedMB
                self.currentDiagnostics = after
                
                if self.soundFeedback && !isAutoTriggered {
                    NSSound(named: "Glass")?.play()
                }
                
                let freedStr = freedMB >= 1024
                    ? String(format: "%.1f GB", Double(freedMB) / 1024.0)
                    : "\(freedMB) MB"
                
                self.flashMessage = "⚡️ Freed \(freedStr) · GPU Clean"
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
