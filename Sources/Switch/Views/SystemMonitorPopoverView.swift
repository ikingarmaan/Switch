import SwiftUI
import AppKit

public struct SystemMonitorPopoverView: View {
    @ObservedObject var service: SystemMonitorService
    
    public init(service: SystemMonitorService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerView
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // MARK: - Scrollable Metrics
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    cpuCard
                    ramCard
                    ssdCard
                    if service.hasBattery {
                        batteryCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // MARK: - Footer & Actions
            footerView
        }
        .frame(width: 330, height: 620)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.65, blue: 0.95).opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("System Monitor")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Live pulsing green dot
                    Circle()
                        .fill(Color(red: 0.25, green: 0.85, blue: 0.45))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(red: 0.25, green: 0.85, blue: 0.45).opacity(0.8), radius: 2)
                }
                
                Text("\(service.chipName) • \(service.coreCount) Cores")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.8))
            }
            
            Spacer()
            
            Button(action: {
                service.sampleMetrics()
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.75))
                    .padding(5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh metrics now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - CPU Card
    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Title & Main Stat
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                    Text("CPU USAGE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                
                Spacer()
                
                Text(String(format: "%.1f%%", service.cpuPercent))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.55, blue: 0.95), Color(red: 0.35, green: 0.85, blue: 0.98)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(service.cpuPercent / 100.0))))
                }
            }
            .frame(height: 6)
            
            // Sub-breakdown (User, System, Idle)
            HStack {
                Text("User: \(String(format: "%.0f%%", service.cpuUserPercent))")
                Spacer()
                Text("System: \(String(format: "%.0f%%", service.cpuSysPercent))")
                Spacer()
                Text("Idle: \(String(format: "%.0f%%", service.cpuIdlePercent))")
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundColor(Color.gray.opacity(0.8))
            
            // Top CPU Apps List
            if !service.topCPUApps.isEmpty {
                VStack(spacing: 5) {
                    ForEach(service.topCPUApps.prefix(3)) { proc in
                        HStack(spacing: 7) {
                            ProcessIconView(service: service, proc: proc)
                            
                            Text(proc.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(5)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - RAM Card
    private var ramCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title & Main Stat
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.72, green: 0.48, blue: 0.98))
                    Text("MEMORY (RAM)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(String(format: "%.1f%%", service.ramPercent))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.72, green: 0.48, blue: 0.98))
                    Text("(\(service.formatBytes(service.ramUsedBytes)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.85))
                }
            }
            
            // Segmented RAM Bar
            GeometryReader { geo in
                let total = max(1, CGFloat(service.ramTotalBytes))
                let appW = (CGFloat(service.ramAppBytes) / total) * geo.size.width
                let wiredW = (CGFloat(service.ramWiredBytes) / total) * geo.size.width
                let compW = (CGFloat(service.ramCompressedBytes) / total) * geo.size.width
                
                HStack(spacing: 1.5) {
                    // App Memory (Cyan)
                    Rectangle()
                        .fill(Color(red: 0.25, green: 0.75, blue: 0.95))
                        .frame(width: max(0, appW))
                    
                    // Wired (Orange)
                    Rectangle()
                        .fill(Color(red: 0.95, green: 0.60, blue: 0.25))
                        .frame(width: max(0, wiredW))
                    
                    // Compressed (Purple)
                    Rectangle()
                        .fill(Color(red: 0.72, green: 0.48, blue: 0.98))
                        .frame(width: max(0, compW))
                    
                    // Free (Dark)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                }
                .cornerRadius(3)
            }
            .frame(height: 6)
            
            // RAM Legend
            HStack(spacing: 8) {
                legendItem(color: Color(red: 0.25, green: 0.75, blue: 0.95), label: "App: \(service.formatBytes(service.ramAppBytes))")
                Spacer()
                legendItem(color: Color(red: 0.95, green: 0.60, blue: 0.25), label: "Wired: \(service.formatBytes(service.ramWiredBytes))")
                Spacer()
                legendItem(color: Color(red: 0.72, green: 0.48, blue: 0.98), label: "Comp: \(service.formatBytes(service.ramCompressedBytes))")
            }
            .font(.system(size: 9, weight: .medium))
            
            // Top RAM Apps List
            if !service.topRAMApps.isEmpty {
                VStack(spacing: 5) {
                    ForEach(service.topRAMApps.prefix(3)) { proc in
                        HStack(spacing: 7) {
                            ProcessIconView(service: service, proc: proc)
                            
                            Text(proc.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(proc.memFormatted)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.72, green: 0.48, blue: 0.98))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(5)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - SSD Card
    private var ssdCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title & Main Stat
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.32, green: 0.85, blue: 0.58))
                    Text("STORAGE (SSD)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(String(format: "%.1f%%", service.ssdPercent))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.32, green: 0.85, blue: 0.58))
                    Text("(\(service.formatBytes(service.ssdFreeBytes)) Free)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.85))
                }
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.18, green: 0.70, blue: 0.45), Color(red: 0.38, green: 0.92, blue: 0.65)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(service.ssdPercent / 100.0))))
                }
            }
            .frame(height: 6)
            
            // Stats Row
            HStack {
                Text("Used: \(service.formatBytes(service.ssdUsedBytes))")
                Spacer()
                Text("Macintosh HD (APFS)")
                Spacer()
                Text("Total: \(service.totalSSDFormatted)")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(Color.gray.opacity(0.8))
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Battery Card
    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title & Main Stat
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: service.isCharging ? "bolt.batteryblock.fill" : (service.batteryPercent <= 20 ? "battery.25" : "battery.100.bolt"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(batteryAccentColor)
                    Text("BATTERY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text("\(service.batteryPercent)%")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(batteryAccentColor)
                    
                    Text(batteryStateLabel)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(batteryAccentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(batteryAccentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: batteryGradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(service.batteryPercent) / 100.0)))
                }
            }
            .frame(height: 6)
            
            // Time remaining row
            if !service.batteryTimeRemaining.isEmpty {
                HStack {
                    Image(systemName: service.isCharging ? "bolt.fill" : "clock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color.gray.opacity(0.8))
                    Text(service.batteryTimeRemaining)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                    Spacer()
                    Text(service.powerSource)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.75))
                }
            }
            
            // Health & Specs Grid
            HStack(spacing: 8) {
                batteryInfoTile(title: "HEALTH", value: "\(service.batteryHealthPercent)%", sub: service.batteryCondition)
                batteryInfoTile(title: "CYCLES", value: "\(service.batteryCycleCount)", sub: "of 1000")
                batteryInfoTile(title: "SOURCE", value: service.isPluggedIn ? "Power Adapter" : "Battery", sub: service.isCharging ? "Charging" : (service.isCharged ? "Full" : "On Battery"))
            }
            
            // Open Battery Settings
            Button(action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 10))
                    Text("Battery Settings...")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9))
                }
                .foregroundColor(Color.white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func batteryInfoTile(title: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.gray.opacity(0.7))
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(Color.gray.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
    
    private var batteryAccentColor: Color {
        if service.isCharging {
            return Color(red: 0.25, green: 0.85, blue: 0.98)
        } else if service.batteryPercent > 40 {
            return Color(red: 0.32, green: 0.85, blue: 0.58)
        } else if service.batteryPercent > 20 {
            return Color(red: 1.0, green: 0.72, blue: 0.20)
        } else {
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }
    
    private var batteryStateLabel: String {
        if service.isCharging {
            return "⚡ Charging"
        } else if service.isCharged {
            return "✓ Charged"
        } else if service.isPluggedIn {
            return "🔌 Plugged In"
        } else {
            return "🔋 Discharging"
        }
    }
    
    private var batteryGradientColors: [Color] {
        if service.isCharging {
            return [Color(red: 0.20, green: 0.65, blue: 0.95), Color(red: 0.35, green: 0.90, blue: 1.0)]
        } else if service.batteryPercent > 40 {
            return [Color(red: 0.18, green: 0.70, blue: 0.45), Color(red: 0.38, green: 0.92, blue: 0.65)]
        } else if service.batteryPercent > 20 {
            return [Color(red: 0.95, green: 0.55, blue: 0.15), Color(red: 1.0, green: 0.75, blue: 0.25)]
        } else {
            return [Color(red: 0.90, green: 0.20, blue: 0.20), Color(red: 1.0, green: 0.40, blue: 0.40)]
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 8) {
            // Display Mode Menu
            Menu {
                ForEach(MonitorDisplayMode.allCases) { mode in
                    Button(action: {
                        service.displayMode = mode
                    }) {
                        HStack {
                            Text(mode.label)
                            if service.displayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 9))
                    Text(service.displayMode.rawValue)
                        .font(.system(size: 10.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
                .foregroundColor(Color.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()
            
            // Open Activity Monitor Button
            Button(action: {
                service.openActivityMonitor()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Activity Monitor")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(Color.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Launch Activity Monitor app")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Helper Views
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .foregroundColor(Color.gray.opacity(0.85))
        }
    }
}

// MARK: - Process Icon View
public struct ProcessIconView: View {
    let service: SystemMonitorService
    let proc: MonitoredProcess
    
    public init(service: SystemMonitorService, proc: MonitoredProcess) {
        self.service = service
        self.proc = proc
    }
    
    public var body: some View {
        let nsImg = service.iconForProcess(pid: proc.pid, displayName: proc.displayName, isApp: proc.isApp)
        Image(nsImage: nsImg)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 14, height: 14)
            .cornerRadius(3)
    }
}
