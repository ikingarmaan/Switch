import SwiftUI
import Cocoa

final class SettingsTabState: ObservableObject {
    @Published var selectedTab: Int = 0
}

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var tabState = SettingsTabState()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Header / Toolbar
            HStack(spacing: 12) {
                tabButton(title: "General", icon: "gearshape.fill", tag: 0)
                tabButton(title: "Switches", icon: "switch.2", tag: 1)
                tabButton(title: "About", icon: "info.circle.fill", tag: 2)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            .padding(.horizontal, 20)
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    if tabState.selectedTab == 0 {
                        generalTab
                    } else if tabState.selectedTab == 1 {
                        switchesTab
                    } else {
                        aboutTab
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 460)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95)
            }
        )
    }
    
    private func tabButton(title: String, icon: String, tag: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                tabState.selectedTab = tag
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(tabState.selectedTab == tag ? .white : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(tabState.selectedTab == tag ? Color.white.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Launch At Login Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Startup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at Login (Always Open on Restart)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Automatically launches Switch whenever your Mac starts up or restarts.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            
            // Menu Bar Icon Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Menu Bar Appearance")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select Menu Bar Icon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 10) {
                        ForEach(settings.availableIcons, id: \.id) { icon in
                            let isSelected = settings.menuBarIcon == icon.id
                            Button(action: {
                                settings.setMenuBarIcon(icon.id)
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: icon.symbol)
                                        .font(.system(size: 18))
                                        .foregroundColor(isSelected ? .accentColor : .white)
                                    Text(icon.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(isSelected ? .white : .gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            
            // Preferences Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Behavior & Options")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                
                VStack(spacing: 12) {
                    // Screen Saver Delay
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Screen Saver Default Duration")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Text("Idle time before screen saver activates when toggled on.")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Picker("", selection: Binding(
                            get: { settings.defaultScreenSaverDelay },
                            set: { settings.setScreenSaverDelay($0) }
                        )) {
                            ForEach(settings.screenSaverDurations, id: \.seconds) { item in
                                Text(item.label).tag(item.seconds)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    
                    Divider().background(Color.white.opacity(0.06))
                    
                    // Sound on Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sound Effects")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Text("Play a subtle sound when toggling switches.")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { settings.playSound },
                            set: { settings.setPlaySound($0) }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .labelsHidden()
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
        }
    }
    
    // MARK: - Switches Tab
    
    private var switchesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visible Switches")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Choose which switches appear in your menu bar popup.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button("Enable All") {
                    settings.enableAllSwitches()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
            }
            
            VStack(spacing: 8) {
                ForEach(SwitchType.allCases.filter { !$0.isActionOnly }) { type in
                    HStack(spacing: 12) {
                        Image(systemName: type.iconName)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                        
                        Text(type.title)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { settings.isSwitchEnabled(type) },
                            set: { settings.setSwitchEnabled(type, isEnabled: $0) }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
            }
        }
    }
    
    // MARK: - About Tab
    
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 10)
            
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 72, height: 72)
                    Image(systemName: "switch.2")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            
            VStack(spacing: 4) {
                Text("Switch")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Version 1.0.0 (macOS Native)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Text("Switch is a fast, lightweight macOS menu bar utility built in Swift & SwiftUI that gives you instant control over your system settings — inspired by Only Switch.")
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 8)
            
            HStack(spacing: 16) {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                .buttonStyle(.plain)
                
                Button("Quit Switch") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.12)))
                .buttonStyle(.plain)
            }
            
            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}
