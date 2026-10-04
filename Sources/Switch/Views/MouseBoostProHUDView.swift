import SwiftUI
import AppKit

public final class MouseBoostHUDState: ObservableObject {
    @Published public var selectedTab: Int = 0
    @Published public var hoveredItem: String? = nil
    public init() {}
}

public struct MouseBoostProHUDView: View {
    @ObservedObject private var service = MouseBoostProService.shared
    @StateObject private var state = MouseBoostHUDState()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header: Title & Active Directory
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.65, blue: 0.25))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("MouseBoost Pro")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(service.currentFinderPath.isEmpty ? "Desktop" : (service.currentFinderPath as NSString).lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    service.copyCurrentPath()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy Path")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Copy current folder path")
                
                Button(action: {
                    service.hideHUD()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            // Segmented Bar: New File / Quick Tools / Mouse Boost Settings
            HStack(spacing: 6) {
                hudTabButton(title: "New File", icon: "plus.circle.fill", tag: 0)
                hudTabButton(title: "Dev & Actions", icon: "terminal.fill", tag: 1)
                hudTabButton(title: "Mouse Settings", icon: "slider.horizontal.3", tag: 2)
            }
            .padding(.horizontal, 14)
            
            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.horizontal, 10)
            
            // Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if state.selectedTab == 0 {
                        newFilesGrid
                    } else if state.selectedTab == 1 {
                        devAndActionsGrid
                    } else {
                        mouseSettingsSection
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 440, height: 490)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13).opacity(0.92))
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.55), radius: 25, x: 0, y: 12)
    }
    
    private func hudTabButton(title: String, icon: String, tag: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                state.selectedTab = tag
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(state.selectedTab == tag ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(state.selectedTab == tag ? Color.white.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tab 1: New File Grid
    
    private var newFilesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create in \(service.currentFinderPath.isEmpty ? "Desktop" : (service.currentFinderPath as NSString).lastPathComponent)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(NewFileType.allCases) { fileType in
                    Button(action: {
                        service.createNewFile(type: fileType)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: fileType.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.98))
                                .frame(width: 18)
                            
                            Text(fileType.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Tab 2: Dev & Finder Quick Actions
    
    private var devAndActionsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Dev Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Developer Tools")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                
                HStack(spacing: 8) {
                    actionButton(title: "Terminal Here", icon: "terminal.fill", color: Color.green) {
                        service.openInTerminal()
                    }
                    actionButton(title: "Open VS Code", icon: "chevron.left.forwardslash.chevron.right", color: Color.blue) {
                        service.openInVSCode()
                    }
                    actionButton(title: "Open Cursor", icon: "cursorarrow.rays", color: Color.purple) {
                        service.openInCursor()
                    }
                }
            }
            
            // Clipboard & Path
            VStack(alignment: .leading, spacing: 8) {
                Text("Clipboard & File Utilities")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                
                VStack(spacing: 6) {
                    rowActionButton(title: "Copy POSIX Path", icon: "doc.on.doc", subtitle: "Copies exact filesystem path") {
                        service.copyCurrentPath()
                    }
                    rowActionButton(title: "Copy File URL (file://)", icon: "link", subtitle: "Copies browser & Markdown URL") {
                        service.copyURLPath()
                    }
                    rowActionButton(title: "Calculate SHA-256 Hash", icon: "lock.shield", subtitle: "Computes checksum of selected file") {
                        service.calculateChecksum()
                    }
                    rowActionButton(title: "Compress to ZIP Archive", icon: "archivebox.fill", subtitle: "Zips selected file/folder in Finder") {
                        service.compressSelectedInFinder()
                    }
                    rowActionButton(title: "Toggle Finder Hidden Files", icon: "eye.fill", subtitle: "Instantly show / hide dotfiles in Finder") {
                        service.toggleFinderHiddenFiles()
                    }
                    rowActionButton(title: "Area Screenshot (Snipping)", icon: "camera.fill", subtitle: "Instant crosshair capture to clipboard") {
                        service.triggerAreaScreenshot()
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 3: Mouse Settings (Wheel, Buttons, Boost)
    
    private var mouseSettingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Scroll Wheel Turbo Boost
            VStack(alignment: .leading, spacing: 8) {
                Text("Scroll Wheel Acceleration")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                
                HStack(spacing: 6) {
                    ForEach(MouseBoostScrollSpeed.allCases) { speed in
                        Button(action: {
                            service.setScrollSpeed(speed)
                        }) {
                            Text(speed.label)
                                .font(.system(size: 11, weight: service.scrollSpeed == speed ? .bold : .medium))
                                .foregroundColor(service.scrollSpeed == speed ? .white : .white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(service.scrollSpeed == speed ? Color(red: 0.95, green: 0.55, blue: 0.20) : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Middle Click Action
            VStack(alignment: .leading, spacing: 8) {
                Text("Middle Click (Wheel Click) Action")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                
                Picker("", selection: Binding(
                    get: { service.middleClickAction },
                    set: { service.setMiddleClickAction($0) }
                )) {
                    ForEach(MouseBoostMiddleClickAction.allCases) { act in
                        Text(act.label).tag(act)
                    }
                }
                .labelsHidden()
            }
            
            // Side Buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Side Buttons Mapping (Mouse 4 & 5)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Button 4 (Back):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Picker("", selection: Binding(
                            get: { service.button4Action },
                            set: { service.setButton4Action($0) }
                        )) {
                            ForEach(MouseBoostSideButtonAction.allCases) { act in
                                Text(act.label).tag(act)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Button 5 (Forward):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Picker("", selection: Binding(
                            get: { service.button5Action },
                            set: { service.setButton5Action($0) }
                        )) {
                            ForEach(MouseBoostSideButtonAction.allCases) { act in
                                Text(act.label).tag(act)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            
            // Invert Scroll Wheel Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invert Mouse Scroll Wheel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Text("Reverses mouse wheel without affecting trackpad natural scrolling.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { service.invertScrollWheel },
                    set: { service.setInvertScrollWheel($0) }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .labelsHidden()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
    }
    
    // MARK: - Helper UI Builders
    
    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func rowActionButton(title: String, icon: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.98))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}
