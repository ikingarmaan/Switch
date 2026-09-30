import Foundation
import Cocoa
import SwiftUI
import Combine
import Darwin
import IOKit.ps
import IOKit

public extension Notification.Name {
    static let systemMonitorDidChange = Notification.Name("SwitchSystemMonitorDidChange")
    static let systemMonitorTick = Notification.Name("SwitchSystemMonitorTick")
}

public enum MonitorDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact = "Compact"
    case stacked = "Stacked"
    case compactWithApp = "With App"
    case minimal = "Mini"
    case textOnly = "Text"
    case values = "Values"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .compact: return "Compact (⚡18% 🧠75% 💾70% 🔋78%)"
        case .stacked: return "Stacked 2-Line (Ultra-Narrow)"
        case .compactWithApp: return "Compact with App (⚡18%(App) 🧠75% 💾70% 🔋78%)"
        case .minimal: return "Mini CPU, RAM & Battery (⚡18% 🧠75% 🔋78%)"
        case .textOnly: return "Text Only (C:18% M:75% S:70% B:78%)"
        case .values: return "Storage Values (⚡18% 🧠6.5G 💾72G 🔋78%)"
        }
    }
}

public struct MonitoredProcess: Identifiable, Sendable {
    public let id: String
    public let pid: Int32
    public let name: String
    public let displayName: String
    public let cpuPercent: Double
    public let memPercent: Double
    public let memBytes: UInt64
    public let memFormatted: String
    public let isApp: Bool
    
    public init(
        pid: Int32,
        name: String,
        displayName: String,
        cpuPercent: Double,
        memPercent: Double,
        memBytes: UInt64,
        memFormatted: String,
        isApp: Bool
    ) {
        self.id = "\(pid)-\(name)"
        self.pid = pid
        self.name = name
        self.displayName = displayName
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
        self.memBytes = memBytes
        self.memFormatted = memFormatted
        self.isApp = isApp
    }
}

public final class SystemMonitorService: ObservableObject, @unchecked Sendable {
    public static let shared = SystemMonitorService()
    
    // MARK: - Published State
    @Published public private(set) var isEnabled: Bool = false
    @Published public var displayMode: MonitorDisplayMode = .compact {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "switch.systemMonitorMode")
            updateMenuBarTitle()
        }
    }
    
    // CPU
    @Published public private(set) var cpuPercent: Double = 0.0
    @Published public private(set) var cpuUserPercent: Double = 0.0
    @Published public private(set) var cpuSysPercent: Double = 0.0
    @Published public private(set) var cpuIdlePercent: Double = 100.0
    
    // RAM
    @Published public private(set) var ramPercent: Double = 0.0
    @Published public private(set) var ramUsedBytes: UInt64 = 0
    @Published public private(set) var ramTotalBytes: UInt64 = 0
    @Published public private(set) var ramFreeBytes: UInt64 = 0
    @Published public private(set) var ramAppBytes: UInt64 = 0
    @Published public private(set) var ramWiredBytes: UInt64 = 0
    @Published public private(set) var ramCompressedBytes: UInt64 = 0
    
    // SSD
    @Published public private(set) var ssdPercent: Double = 0.0
    @Published public private(set) var ssdUsedBytes: UInt64 = 0
    @Published public private(set) var ssdTotalBytes: UInt64 = 0
    @Published public private(set) var ssdFreeBytes: UInt64 = 0
    
    // Battery
    @Published public private(set) var hasBattery: Bool = false
    @Published public private(set) var batteryPercent: Int = 100
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var isPluggedIn: Bool = false
    @Published public private(set) var isCharged: Bool = false
    @Published public private(set) var batteryTimeRemaining: String = ""
    @Published public private(set) var batteryHealthPercent: Int = 100
    @Published public private(set) var batteryCycleCount: Int = 0
    @Published public private(set) var batteryCondition: String = "Normal"
    @Published public private(set) var powerSource: String = "Battery Power"
    
    // Top Consumer Apps
    @Published public private(set) var topCPUApps: [MonitoredProcess] = []
    @Published public private(set) var topRAMApps: [MonitoredProcess] = []
    @Published public private(set) var topCPUApp: MonitoredProcess? = nil
    @Published public private(set) var topRAMApp: MonitoredProcess? = nil
    
    // Menu Bar Display Text & Summary
    @Published public private(set) var menuBarText: String = ""
    @Published public private(set) var shortSummary: String = "Off"
    
    // Hardware Info
    public let chipName: String
    public let coreCount: Int
    public let totalRAMFormatted: String
    public let totalSSDFormatted: String
    
    // MARK: - Private Properties
    private var statusItem: NSStatusItem?
    private var popover: NSPopover = NSPopover()
    private var updateTimer: Timer?
    private var prevCpuLoad: host_cpu_load_info?
    private var isSampling: Bool = false
    
    // Cached app icons
    private var iconCache: [Int32: NSImage] = [:]
    
    private init() {
        // Detect chip name
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chip = "Apple Silicon"
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            chip = String(cString: buffer)
        }
        self.chipName = chip.replacingOccurrences(of: "(R)", with: "")
                            .replacingOccurrences(of: "(TM)", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        self.coreCount = ProcessInfo.processInfo.processorCount
        let totalMem = ProcessInfo.processInfo.physicalMemory
        self.totalRAMFormatted = String(format: "%.0f GB", Double(totalMem) / 1_000_000_000.0)
        
        // Root filesystem size
        var fs = statfs()
        if statfs("/", &fs) == 0 {
            let totalSSD = UInt64(fs.f_blocks) * UInt64(fs.f_bsize)
            self.totalSSDFormatted = String(format: "%.0f GB", Double(totalSSD) / 1_000_000_000.0)
        } else {
            self.totalSSDFormatted = "SSD"
        }
        
        // Restore display mode preference
        if let savedMode = UserDefaults.standard.string(forKey: "switch.systemMonitorMode"),
           let mode = MonitorDisplayMode(rawValue: savedMode) {
            self.displayMode = mode
        }
        
        setupPopover()
    }
    
    // MARK: - Public Control
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            start()
        } else {
            stop()
        }
    }
    
    public func restoreStateIfNeeded() {
        let wasActive = UserDefaults.standard.bool(forKey: "switch.systemMonitorEnabled")
        if wasActive {
            start()
        }
    }
    
    public func start() {
        guard !isEnabled else { return }
        isEnabled = true
        shortSummary = "⚡ ... · 🧠 ... · 💾 ..."
        UserDefaults.standard.set(true, forKey: "switch.systemMonitorEnabled")
        
        setupStatusItem()
        sampleMetricsImmediate()
        
        // Timer runs every 2.0s on common run loop
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sampleMetrics()
        }
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        NotificationCenter.default.post(name: .systemMonitorDidChange, object: true)
    }
    
    public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        UserDefaults.standard.set(false, forKey: "switch.systemMonitorEnabled")
        
        updateTimer?.invalidate()
        updateTimer = nil
        
        if popover.isShown {
            popover.performClose(nil)
        }
        
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        
        shortSummary = "Off"
        menuBarText = ""
        NotificationCenter.default.post(name: .systemMonitorDidChange, object: false)
    }
    
    // MARK: - Status Item & Popover Setup
    
    private func setupStatusItem() {
        if statusItem != nil { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        button.title = "⚡... 🧠... 💾... 🔋..."
        button.toolTip = "System Monitor (CPU, RAM, SSD, Battery)\nClick for live details & top apps"
    }
    
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 330, height: 640)
        popover.contentViewController = NSHostingController(rootView: SystemMonitorPopoverView(service: self))
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Context menu on right click
            let menu = NSMenu()
            
            let titleItem = NSMenuItem(title: "System Monitor", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())
            
            let actItem = NSMenuItem(title: "Open Activity Monitor...", action: #selector(openActivityMonitor), keyEquivalent: "")
            actItem.target = self
            menu.addItem(actItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let modeSubmenu = NSMenu()
            for mode in MonitorDisplayMode.allCases {
                let mItem = NSMenuItem(title: mode.label, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
                mItem.target = self
                mItem.representedObject = mode
                if mode == self.displayMode {
                    mItem.state = .on
                }
                modeSubmenu.addItem(mItem)
            }
            let modeMenuItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
            modeMenuItem.submenu = modeSubmenu
            menu.addItem(modeMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let turnOffItem = NSMenuItem(title: "Turn Off Monitor", action: #selector(turnOffFromMenu), keyEquivalent: "")
            turnOffItem.target = self
            menu.addItem(turnOffItem)
            
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            togglePopover(sender)
        }
    }
    
    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? MonitorDisplayMode {
            self.displayMode = mode
        }
    }
    
    @objc public func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }
    
    @objc private func turnOffFromMenu() {
        stop()
    }
    
    public func togglePopover(_ sender: NSStatusBarButton? = nil) {
        let anchorButton = sender ?? statusItem?.button
        guard let button = anchorButton else { return }
        
        if popover.isShown {
            popover.performClose(button)
        } else {
            sampleMetrics()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    // MARK: - Metrics Sampling
    
    private func sampleMetricsImmediate() {
        sampleMetrics()
    }
    
    public func sampleMetrics() {
        guard !isSampling else { return }
        isSampling = true
        
        let previousLoad = self.prevCpuLoad
        let needDetailedProcesses = popover.isShown
        
        Task.detached(priority: .userInitiated) { [weak self] in
            // 1. CPU Mach host statistics
            var cpuLoad = host_cpu_load_info()
            var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
            let cpuResult = withUnsafeMutablePointer(to: &cpuLoad) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
                }
            }
            
            var cpuP: Double = 0.0
            var userP: Double = 0.0
            var sysP: Double = 0.0
            var idleP: Double = 100.0
            
            if cpuResult == KERN_SUCCESS, let prev = previousLoad {
                let userDelta = Double(cpuLoad.cpu_ticks.0 - prev.cpu_ticks.0)
                let sysDelta = Double(cpuLoad.cpu_ticks.1 - prev.cpu_ticks.1)
                let idleDelta = Double(cpuLoad.cpu_ticks.2 - prev.cpu_ticks.2)
                let niceDelta = Double(cpuLoad.cpu_ticks.3 - prev.cpu_ticks.3)
                let totalDelta = userDelta + sysDelta + idleDelta + niceDelta
                
                if totalDelta > 0 {
                    userP = (userDelta / totalDelta) * 100.0
                    sysP = (sysDelta / totalDelta) * 100.0
                    idleP = (idleDelta / totalDelta) * 100.0
                    cpuP = ((userDelta + sysDelta + niceDelta) / totalDelta) * 100.0
                }
            }
            
            // 2. RAM Mach VM statistics
            var vmStats = vm_statistics64()
            var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
            let vmResult = withUnsafeMutablePointer(to: &vmStats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
                }
            }
            
            let totalRAM = ProcessInfo.processInfo.physicalMemory
            var ramP: Double = 0.0
            var usedRAM: UInt64 = 0
            var freeRAM: UInt64 = 0
            var appRAM: UInt64 = 0
            var wiredRAM: UInt64 = 0
            var compressedRAM: UInt64 = 0
            
            if vmResult == KERN_SUCCESS {
                let pageSize = UInt64(vm_kernel_page_size)
                appRAM = (UInt64(vmStats.internal_page_count) > UInt64(vmStats.purgeable_count))
                    ? (UInt64(vmStats.internal_page_count) - UInt64(vmStats.purgeable_count)) * pageSize
                    : 0
                wiredRAM = UInt64(vmStats.wire_count) * pageSize
                compressedRAM = UInt64(vmStats.compressor_page_count) * pageSize
                usedRAM = appRAM + wiredRAM + compressedRAM
                freeRAM = totalRAM > usedRAM ? (totalRAM - usedRAM) : 0
                ramP = totalRAM > 0 ? (Double(usedRAM) / Double(totalRAM)) * 100.0 : 0.0
            }
            
            // 3. SSD statfs
            var fs = statfs()
            var ssdP: Double = 0.0
            var usedSSD: UInt64 = 0
            var totalSSD: UInt64 = 0
            var freeSSD: UInt64 = 0
            
            if statfs("/", &fs) == 0 {
                let blockSize = UInt64(fs.f_bsize)
                totalSSD = UInt64(fs.f_blocks) * blockSize
                freeSSD = UInt64(fs.f_bavail) * blockSize
                usedSSD = totalSSD > freeSSD ? (totalSSD - freeSSD) : 0
                ssdP = totalSSD > 0 ? (Double(usedSSD) / Double(totalSSD)) * 100.0 : 0.0
            }
            
            // 4. Top Processes via ps
            let topLists = Self.fetchTopProcesses(limit: needDetailedProcesses ? 5 : 2, totalRAM: totalRAM)
            
            // 5. Battery Details via IOKit
            let batData = Self.fetchBatteryDetails()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.prevCpuLoad = cpuLoad
                
                // Only update CPU % if we had a previous sample (avoids initial 0 glitch)
                if previousLoad != nil {
                    self.cpuPercent = min(100.0, max(0.0, cpuP))
                    self.cpuUserPercent = userP
                    self.cpuSysPercent = sysP
                    self.cpuIdlePercent = idleP
                }
                
                self.ramPercent = min(100.0, max(0.0, ramP))
                self.ramUsedBytes = usedRAM
                self.ramTotalBytes = totalRAM
                self.ramFreeBytes = freeRAM
                self.ramAppBytes = appRAM
                self.ramWiredBytes = wiredRAM
                self.ramCompressedBytes = compressedRAM
                
                self.ssdPercent = min(100.0, max(0.0, ssdP))
                self.ssdUsedBytes = usedSSD
                self.ssdTotalBytes = totalSSD
                self.ssdFreeBytes = freeSSD
                
                self.hasBattery = batData.hasBattery
                self.batteryPercent = batData.percent
                self.isCharging = batData.isCharging
                self.isPluggedIn = batData.isPluggedIn
                self.isCharged = batData.isCharged
                self.batteryTimeRemaining = batData.timeRemaining
                self.batteryHealthPercent = batData.healthPercent
                self.batteryCycleCount = batData.cycleCount
                self.batteryCondition = batData.condition
                self.powerSource = batData.powerSource
                
                self.topCPUApps = topLists.cpuList
                self.topRAMApps = topLists.ramList
                self.topCPUApp = topLists.cpuList.first
                self.topRAMApp = topLists.ramList.first
                
                self.updateMenuBarTitle()
                self.isSampling = false
                
                NotificationCenter.default.post(name: .systemMonitorTick, object: nil)
            }
        }
    }
    
    // MARK: - Process Fetching
    
    private nonisolated static func fetchTopProcesses(limit: Int, totalRAM: UInt64) -> (cpuList: [MonitoredProcess], ramList: [MonitoredProcess]) {
        let script = "ps -c -A -o %cpu,%mem,pid,command -r | head -n \(limit + 2); echo '===SPLIT==='; ps -c -A -o %mem,%cpu,pid,command -m | head -n \(limit + 2)"
        
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard let text = String(data: data, encoding: .utf8) else {
                return ([], [])
            }
            
            let sections = text.components(separatedBy: "===SPLIT===")
            let cpuText = sections.first ?? ""
            let ramText = sections.count > 1 ? sections[1] : ""
            
            let cpuApps = parseProcesses(from: cpuText, isCpuSorted: true, limit: limit, totalRAM: totalRAM)
            let ramApps = parseProcesses(from: ramText, isCpuSorted: false, limit: limit, totalRAM: totalRAM)
            
            return (cpuApps, ramApps)
        } catch {
            return ([], [])
        }
    }
    
    private nonisolated static func parseProcesses(from rawText: String, isCpuSorted: Bool, limit: Int, totalRAM: UInt64) -> [MonitoredProcess] {
        var results: [MonitoredProcess] = []
        let lines = rawText.split(separator: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("%CPU") || trimmed.hasPrefix("%MEM") {
                continue
            }
            
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 4 else { continue }
            
            let val1 = Double(parts[0]) ?? 0.0
            let val2 = Double(parts[1]) ?? 0.0
            guard let pid = Int32(parts[2]) else { continue }
            let rawName = parts.dropFirst(3).joined(separator: " ")
            
            let cpuVal = isCpuSorted ? val1 : val2
            let memVal = isCpuSorted ? val2 : val1
            
            // Clean process name
            let (displayName, isApp) = cleanProcessName(rawName: rawName, pid: pid)
            
            let memBytes = UInt64((memVal / 100.0) * Double(totalRAM))
            let memFormatted: String
            if memBytes >= 1_000_000_000 {
                memFormatted = String(format: "%.1f GB", Double(memBytes) / 1_000_000_000.0)
            } else {
                memFormatted = String(format: "%.0f MB", Double(memBytes) / 1_000_000.0)
            }
            
            let proc = MonitoredProcess(
                pid: pid,
                name: rawName,
                displayName: displayName,
                cpuPercent: cpuVal,
                memPercent: memVal,
                memBytes: memBytes,
                memFormatted: memFormatted,
                isApp: isApp
            )
            results.append(proc)
            
            if results.count >= limit {
                break
            }
        }
        return results
    }
    
    private nonisolated static func cleanProcessName(rawName: String, pid: Int32) -> (String, Bool) {
        // Check NSRunningApplication first for GUI app names
        if let app = NSRunningApplication(processIdentifier: pid),
           let appName = app.localizedName, !appName.isEmpty {
            return (appName, true)
        }
        
        var name = rawName
        var isApp = false
        
        if name.contains("Antigravity") {
            return ("Antigravity", true)
        } else if name.contains("Google Chrome") {
            return ("Chrome", true)
        } else if name.contains("Arc") {
            return ("Arc", true)
        } else if name.contains("Safari") || name.contains("WebContent") {
            return ("Safari", true)
        } else if name.contains("Xcode") {
            return ("Xcode", true)
        } else if name.contains("Switch") {
            return ("Switch", true)
        } else if name.contains("Stats") {
            return ("Stats", true)
        } else if name.contains("WhatsApp") {
            return ("WhatsApp", true)
        } else if name.contains("Finder") {
            return ("Finder", true)
        } else if name.contains("WindowServer") {
            return ("WindowServer", false)
        } else if name.contains("Dock") {
            return ("Dock", false)
        } else if name.contains("language_server") {
            return ("Language Server", false)
        } else if name.contains("Helper") {
            name = name.replacingOccurrences(of: " Helper", with: "")
                       .replacingOccurrences(of: " (Renderer)", with: "")
                       .replacingOccurrences(of: " (GPU)", with: "")
            isApp = true
        }
        
        return (name, isApp)
    }
    
    // MARK: - App Icon Resolution
    
    public func iconForProcess(pid: Int32, displayName: String, isApp: Bool) -> NSImage {
        if let cached = iconCache[pid] {
            return cached
        }
        
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            iconCache[pid] = icon
            return icon
        }
        
        if let match = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(displayName) == .orderedSame
        }), let icon = match.icon {
            iconCache[pid] = icon
            return icon
        }
        
        let symbolName = isApp ? "app.badge.fill" : "gearshape.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        iconCache[pid] = img
        return img
    }
    
    // MARK: - Menu Bar Formatter
    
    private func updateMenuBarTitle() {
        let cpuStr = String(format: "%.0f%%", cpuPercent)
        let ramStr = String(format: "%.0f%%", ramPercent)
        let ssdStr = String(format: "%.0f%%", ssdPercent)
        let batStr = "\(batteryPercent)%"
        let batIcon: String
        if isCharging {
            batIcon = "⚡"
        } else if isPluggedIn {
            batIcon = "🔌"
        } else if batteryPercent <= 20 {
            batIcon = "🪫"
        } else {
            batIcon = "🔋"
        }
        let batDisplay = hasBattery ? " \(batIcon)\(batStr)" : ""
        let batDisplayStacked = hasBattery ? "\(batIcon)\(batStr)" : ""
        
        // Short summary for Switch row subtitle
        self.shortSummary = "⚡\(cpuStr) 🧠\(ramStr) 💾\(ssdStr)\(batDisplay)"
        
        guard let button = statusItem?.button else { return }
        
        let cpuTopAppName = topCPUApp?.displayName ?? ""
        let shortTopApp: String
        if cpuTopAppName.count > 6 {
            shortTopApp = String(cpuTopAppName.prefix(5)) + "…"
        } else {
            shortTopApp = cpuTopAppName
        }
        
        switch displayMode {
        case .compact:
            button.attributedTitle = NSAttributedString()
            button.title = "⚡\(cpuStr) 🧠\(ramStr) 💾\(ssdStr)\(batDisplay)"
            
        case .stacked:
            let appSuffix = !shortTopApp.isEmpty ? " \(shortTopApp)" : ""
            let topText = "⚡\(cpuStr)\(appSuffix)  \(batDisplayStacked)\n"
            let bottomText = "🧠\(ramStr) 💾\(ssdStr)"
            
            let para = NSMutableParagraphStyle()
            para.alignment = .left
            para.maximumLineHeight = 11.0
            para.minimumLineHeight = 11.0
            
            let attr = NSMutableAttributedString()
            attr.append(NSAttributedString(string: topText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold),
                .paragraphStyle: para
            ]))
            attr.append(NSAttributedString(string: bottomText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
                .paragraphStyle: para
            ]))
            button.attributedTitle = attr
            
        case .compactWithApp:
            let appSuffix = !shortTopApp.isEmpty ? "(\(shortTopApp)) " : ""
            button.attributedTitle = NSAttributedString()
            button.title = "⚡\(cpuStr)\(appSuffix)🧠\(ramStr) 💾\(ssdStr)\(batDisplay)"
            
        case .minimal:
            button.attributedTitle = NSAttributedString()
            button.title = "⚡\(cpuStr) 🧠\(ramStr)\(batDisplay)"
            
        case .textOnly:
            let batTextOnly = hasBattery ? " B:\(batteryPercent)%" : ""
            button.attributedTitle = NSAttributedString()
            button.title = "C:\(cpuStr) M:\(ramStr) S:\(ssdStr)\(batTextOnly)"
            
        case .values:
            let ramGB = Double(ramUsedBytes) / 1_000_000_000.0
            let ssdFreeGB = Double(ssdFreeBytes) / 1_000_000_000.0
            button.attributedTitle = NSAttributedString()
            button.title = "⚡\(cpuStr) 🧠\(String(format: "%.1fG", ramGB)) 💾\(String(format: "%.0fG", ssdFreeGB))\(batDisplay)"
        }
        
        self.menuBarText = button.title
        
        // Tooltip
        let topRamAppStr = topRAMApp != nil ? "\nTop RAM App: \(topRAMApp!.displayName) (\(topRAMApp!.memFormatted))" : ""
        let topCpuAppStr = topCPUApp != nil ? "\nTop CPU App: \(topCPUApp!.displayName) (\(String(format: "%.1f%%", topCPUApp!.cpuPercent)))" : ""
        let batTooltip = hasBattery ? "\nBattery: \(batStr) (\(batteryTimeRemaining)) • Health: \(batteryHealthPercent)% (\(batteryCondition)) • Cycles: \(batteryCycleCount)" : ""
        button.toolTip = "System Monitor\nCPU: \(cpuStr)\(topCpuAppStr)\nRAM: \(ramStr) (\(formatBytes(ramUsedBytes)) / \(totalRAMFormatted))\(topRamAppStr)\nSSD: \(ssdStr) (\(formatBytes(ssdFreeBytes)) Free of \(totalSSDFormatted))\(batTooltip)\nClick for detailed breakdown."
    }
    
    // MARK: - Battery Telemetry Fetcher
    
    private nonisolated static func fetchBatteryDetails() -> (
        hasBattery: Bool,
        percent: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        isCharged: Bool,
        timeRemaining: String,
        healthPercent: Int,
        cycleCount: Int,
        condition: String,
        powerSource: String
    ) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return (false, 100, false, true, true, "AC Power", 100, 0, "Normal", "AC Power")
        }
        
        var foundBattery = false
        var percent = 100
        var isCharging = false
        var isPluggedIn = false
        var isCharged = false
        var timeRemaining = ""
        var pwrSource = "Battery Power"
        
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let isPresent = (desc["Is Present"] as? Bool) ?? ((desc["Is Present"] as? Int) == 1)
                if isPresent {
                    foundBattery = true
                    percent = desc["Current Capacity"] as? Int ?? percent
                    let chargingVal = (desc["Is Charging"] as? Bool) ?? ((desc["Is Charging"] as? Int) == 1)
                    isCharging = chargingVal
                    
                    let pState = desc["Power Source State"] as? String ?? ""
                    pwrSource = pState
                    isPluggedIn = (pState == "AC Power" || isCharging)
                    
                    if percent >= 100 && isPluggedIn {
                        isCharged = true
                        timeRemaining = "Fully Charged"
                    } else if isCharging {
                        if let timeToFull = desc["Time to Full Charge"] as? Int, timeToFull > 0 {
                            let h = timeToFull / 60
                            let m = timeToFull % 60
                            timeRemaining = h > 0 ? "\(h)h \(m)m until full" : "\(m)m until full"
                        } else {
                            timeRemaining = "Charging..."
                        }
                    } else {
                        if let timeToEmpty = desc["Time to Empty"] as? Int, timeToEmpty > 0 {
                            let h = timeToEmpty / 60
                            let m = timeToEmpty % 60
                            timeRemaining = h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
                        } else {
                            timeRemaining = "Calculating..."
                        }
                    }
                    break
                }
            }
        }
        
        if !foundBattery {
            return (false, 100, false, true, true, "AC Power", 100, 0, "Normal", "AC Power")
        }
        
        // IOKit AppleSmartBattery for Health & Cycles
        var cycles = 0
        var health = 100
        var condition = "Normal"
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                cycles = dict["CycleCount"] as? Int ?? 0
                let maxCap = dict["MaxCapacity"] as? Int ?? 100
                let bData = dict["BatteryData"] as? [String: Any]
                let designCap = (bData?["DesignCapacity"] as? Int) ?? (dict["DesignCapacity"] as? Int) ?? 0
                let nominalCap = (bData?["NominalChargeCapacity"] as? Int) ?? (dict["NominalChargeCapacity"] as? Int) ?? 0
                if designCap > 0 && nominalCap > 0 {
                    health = max(1, min(100, Int((Double(nominalCap) / Double(designCap)) * 100.0)))
                } else {
                    health = maxCap
                }
                
                if let installed = dict["BatteryInstalled"] as? Bool, !installed {
                    condition = "No Battery"
                } else if health < 80 {
                    condition = "Service Recommended"
                } else {
                    condition = "Normal"
                }
            }
        }
        
        return (true, percent, isCharging, isPluggedIn, isCharged, timeRemaining, health, cycles, condition, pwrSource)
    }
    
    public func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000.0)
        } else if bytes >= 1_000_000 {
            return String(format: "%.0f MB", Double(bytes) / 1_000_000.0)
        } else {
            return "\(bytes / 1024) KB"
        }
    }
}
