import SwiftUI
import AppKit

public enum AppFilterMode: String, CaseIterable, Identifiable {
    case all = "All Apps"
    case user = "User Apps"
    case system = "System Apps"
    case large = "Large (> 500MB)"
    
    public var id: String { rawValue }
}

public enum AppSortMode: String, CaseIterable, Identifiable {
    case sizeDesc = "Largest Size"
    case dataDesc = "Largest App Data"
    case nameAsc = "Name (A-Z)"
    
    public var id: String { rawValue }
}

public final class MacCleanerViewState: ObservableObject {
    @Published public var selectedTab: Int = 0 // 0: App Uninstaller, 1: System Junk
    @Published public var searchText: String = ""
    @Published public var filterMode: AppFilterMode = .all
    @Published public var sortMode: AppSortMode = .sizeDesc
    @Published public var expandedAppId: UUID? = nil
    @Published public var appToReset: InstalledAppInfo? = nil
    @Published public var appToUninstall: InstalledAppInfo? = nil
    @Published public var showResetAlert: Bool = false
    @Published public var showUninstallAlert: Bool = false
    
    public init() {}
}

public struct MacCleanerView: View {
    @ObservedObject private var cleaner = CleanCacheService.shared
    @StateObject private var state = MacCleanerViewState()
    
    public init() {}
    
    private var filteredApps: [InstalledAppInfo] {
        var list = cleaner.installedApps
        
        // Search filter
        if !state.searchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(state.searchText) ||
                $0.bundleId.localizedCaseInsensitiveContains(state.searchText)
            }
        }
        
        // Category filter
        switch state.filterMode {
        case .all:
            break
        case .user:
            list = list.filter { !$0.isSystemApp }
        case .system:
            list = list.filter { $0.isSystemApp }
        case .large:
            list = list.filter { $0.totalBytes >= 500 * 1024 * 1024 }
        }
        
        // Sort
        switch state.sortMode {
        case .sizeDesc:
            list.sort { $0.totalBytes > $1.totalBytes }
        case .dataDesc:
            list.sort { $0.appDataBytes > $1.appDataBytes }
        case .nameAsc:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        
        return list
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Tab Content
            if state.selectedTab == 0 {
                appUninstallerView
            } else {
                systemJunkView
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .alert(isPresented: $state.showResetAlert) {
            Alert(
                title: Text("Reset App Data for \(state.appToReset?.name ?? "App")?"),
                message: Text("This will delete all caches, saved state, preferences, and container files (\(state.appToReset?.formattedDataSize ?? "0 B")) to start fresh. The application itself will NOT be deleted."),
                primaryButton: .destructive(Text("Reset Data")) {
                    if let app = state.appToReset {
                        cleaner.resetAppData(for: app)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $state.showUninstallAlert) {
            Alert(
                title: Text("Uninstall \(state.appToUninstall?.name ?? "App") Completely?"),
                message: Text("This will permanently delete the application bundle AND all associated data (\(state.appToUninstall?.formattedTotalSize ?? "0 B"))."),
                primaryButton: .destructive(Text("Uninstall App")) {
                    if let app = state.appToUninstall {
                        cleaner.uninstallApp(for: app)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(red: 0.38, green: 0.82, blue: 0.55))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Cleaner & App Uninstaller")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Disk Free: \(cleaner.diagnostics.formattedFreeDisk) · Total: \(cleaner.diagnostics.formattedTotalDisk)")
                        .font(.system(size: 11))
                        .foregroundColor(Color.gray.opacity(0.85))
                }
            }
            
            Spacer()
            
            // Segmented Picker
            Picker("", selection: $state.selectedTab) {
                Text("📦 App Uninstaller & Data Wiper").tag(0)
                Text("⚡️ System Junk & Caches").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 380)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
    }
    
    // MARK: - Tab 1: App Uninstaller & Data Wiper
    
    private var appUninstallerView: some View {
        VStack(spacing: 0) {
            // Control Bar (Search, Filters, Sort)
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search installed apps...", text: $state.searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                    if !state.searchText.isEmpty {
                        Button(action: { state.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .frame(width: 240)
                
                // Filter Tabs
                HStack(spacing: 4) {
                    ForEach(AppFilterMode.allCases) { mode in
                        Button(action: { state.filterMode = mode }) {
                            Text(mode.rawValue)
                                .font(.system(size: 11.5, weight: state.filterMode == mode ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(state.filterMode == mode ? Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.25) : Color.white.opacity(0.05))
                                )
                                .foregroundColor(state.filterMode == mode ? Color(red: 0.40, green: 0.88, blue: 0.60) : .white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // Sort Menu
                Menu {
                    ForEach(AppSortMode.allCases) { mode in
                        Button(action: { state.sortMode = mode }) {
                            HStack {
                                Text(mode.rawValue)
                                if state.sortMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(state.sortMode.rawValue)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .foregroundColor(.white.opacity(0.85))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Rescan Button
                Button(action: {
                    cleaner.scanInstalledApps()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(cleaner.isScanningApps ? Color.accentColor : Color.white.opacity(0.8))
                        .rotationEffect(.degrees(cleaner.isScanningApps ? 360 : 0))
                        .animation(cleaner.isScanningApps ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: cleaner.isScanningApps)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Rescan Installed Apps")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // App List
            if cleaner.isScanningApps && cleaner.installedApps.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Scanning Installed Applications & Hidden Data Residues...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else if filteredApps.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.6))
                    Text("No applications found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredApps) { app in
                            appRow(app)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
    
    private func appRow(_ app: InstalledAppInfo) -> some View {
        let isExpanded = state.expandedAppId == app.id
        
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                // App Icon
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                    .resizable()
                    .frame(width: 38, height: 38)
                    .cornerRadius(8)
                
                // Name & Version & Details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if app.isSystemApp {
                            Text("macOS System")
                                .font(.system(size: 9.5, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.2)))
                                .foregroundColor(Color.blue.opacity(0.9))
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text("v\(app.version)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("App: \(app.formattedAppSize)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        if app.appDataBytes > 0 {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Data: \(app.formattedDataSize)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.25))
                        }
                    }
                }
                
                Spacer()
                
                // Total Size Badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.formattedTotalSize)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white)
                    if !app.residuals.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.expandedAppId = isExpanded ? nil : app.id
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text("\(app.residuals.count) data folders")
                                    .font(.system(size: 10.5))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(Color.gray.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 100, alignment: .trailing)
                
                // Action Buttons
                HStack(spacing: 8) {
                    // Reset App Data Button (Wipes all data files without deleting app)
                    Button(action: {
                        state.appToReset = app
                        state.showResetAlert = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "eraser.fill")
                            Text("Reset Data")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.18)))
                        .foregroundColor(Color(red: 1.0, green: 0.70, blue: 0.30))
                    }
                    .buttonStyle(.plain)
                    .help("Delete all caches, preferences, and state to reset app to fresh install")
                    .disabled(app.appDataBytes == 0)
                    .opacity(app.appDataBytes == 0 ? 0.4 : 1.0)
                    
                    // Uninstall App Button (Deletes .app + all residuals)
                    if !app.isSystemApp {
                        Button(action: {
                            state.appToUninstall = app
                            state.showUninstallAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("Uninstall")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.22)))
                            .foregroundColor(Color(red: 1.0, green: 0.40, blue: 0.40))
                        }
                        .buttonStyle(.plain)
                        .help("Completely remove application and all associated data")
                    } else {
                        Button(action: {
                            state.appToReset = app
                            state.showResetAlert = true
                        }) {
                            Text("System Protected")
                                .font(.system(size: 10.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
            
            // Expanded Residual Folders
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Associated Files & Data Residues:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.gray.opacity(0.9))
                        .padding(.top, 6)
                        .padding(.horizontal, 16)
                    
                    ForEach(app.residuals) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.25))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.category)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                Text(item.path)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Text(item.formattedSize)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.85))
                            
                            Button(action: {
                                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                            }) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                )
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }
    
    // MARK: - Tab 2: System Junk & Caches
    
    private var systemJunkView: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Storage Overview Card
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cleanable Junk & Temporary Files")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        Text(cleaner.diagnostics.formattedCleanable)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.38, green: 0.85, blue: 0.55))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        cleaner.cleanNow()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .rotationEffect(.degrees(cleaner.isCleaning ? 360 : 0))
                                .animation(cleaner.isCleaning ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: cleaner.isCleaning)
                            Text(cleaner.isCleaning ? "Cleaning Mac..." : "Clean All Junk Now")
                                .font(.system(size: 13.5, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.76, blue: 0.52), Color(red: 0.18, green: 0.60, blue: 0.40)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(cleaner.isCleaning)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                
                // Categories List
                VStack(spacing: 10) {
                    categoryRow(
                        title: "User Application Caches",
                        desc: "Browser caches, WebKit data, Slack, Spotify, Discord, and app render caches",
                        sizeBytes: cleaner.diagnostics.userCachesBytes,
                        icon: "app.badge.fill",
                        isOn: $cleaner.cleanUserCaches
                    )
                    
                    categoryRow(
                        title: "Developer & Build Artifacts",
                        desc: "Xcode DerivedData, Archives, iOS Simulator logs, npm, pip, CocoaPods, and Homebrew",
                        sizeBytes: cleaner.diagnostics.devCachesBytes,
                        icon: "hammer.fill",
                        isOn: $cleaner.cleanDevCaches
                    )
                    
                    categoryRow(
                        title: "System & Crash Logs",
                        desc: "Old application crash reports, diagnostic spin dumps, and log files",
                        sizeBytes: cleaner.diagnostics.logsBytes,
                        icon: "doc.text.fill",
                        isOn: $cleaner.cleanLogs
                    )
                    
                    categoryRow(
                        title: "Temporary & QuickLook Files",
                        desc: "QuickLook thumbnail cache, Cocoa temporary items, and DNS cache flush",
                        sizeBytes: cleaner.diagnostics.tempBytes,
                        icon: "clock.arrow.circlepath",
                        isOn: $cleaner.cleanTemp
                    )
                    
                    categoryRow(
                        title: "macOS Trash Bin",
                        desc: "Deleted files residing in the user Trash bin",
                        sizeBytes: cleaner.diagnostics.trashBytes,
                        icon: "trash.fill",
                        isOn: $cleaner.emptyTrash
                    )
                }
                
                // Automation Options
                VStack(alignment: .leading, spacing: 10) {
                    Text("Automation & Feedback")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    HStack {
                        Toggle(isOn: Binding(
                            get: { cleaner.isAutoGuardEnabled },
                            set: { cleaner.setAutoGuardEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Clean Guard")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Automatically clears junk files when accumulated caches exceed 5 GB")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    
                    HStack {
                        Toggle(isOn: $cleaner.soundFeedback) {
                            Text("Play Sound Effect on Clean")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .toggleStyle(.switch)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
            .padding(20)
        }
    }
    
    private func categoryRow(title: String, desc: String, sizeBytes: Int64, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(red: 0.38, green: 0.85, blue: 0.55))
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(minWidth: 70, alignment: .trailing)
            
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}
