import SwiftUI

public struct SwitchListView: View {
    @StateObject private var viewModel = SwitchListViewModel()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Notch / Accent Pill Indicator (as seen in screenshot)
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.28, green: 0.76, blue: 0.52))
                    .frame(width: 48, height: 4)
                    .padding(.top, 5)
                    .padding(.bottom, 6)
                Spacer()
            }
            
            // Switch List
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(viewModel.visibleSwitches) { item in
                        SwitchRowView(
                            item: item,
                            onToggle: { newValue in
                                viewModel.toggleSwitch(item: item, newValue: newValue)
                            },
                            onAction: {
                                viewModel.triggerAction(type: item.type)
                            }
                        )
                        
                        if item.id != viewModel.visibleSwitches.last?.id {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 680)
            
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.top, 4)
            
            // Footer bar with Quick Utilities
            HStack(spacing: 12) {
                // Lock Mac Button
                Button(action: {
                    viewModel.triggerAction(type: .lockScreen)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Lock")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // Empty Trash Button
                Button(action: {
                    viewModel.triggerAction(type: .emptyTrash)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Trash")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // Force Quit Apps Button
                Button(action: {
                    viewModel.triggerAction(type: .forceQuitApps)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.app.fill")
                        Text("Quit Apps")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Settings Button
                Button(action: {
                    SettingsWindowManager.shared.showSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help("Settings")
                
                // Refresh Button
                Button(action: {
                    viewModel.refreshAll()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewModel.isRefreshing ? .accentColor : .white.opacity(0.7))
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(viewModel.isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help("Refresh Statuses")
                
                // Quit Button
                Button(action: {
                    viewModel.quitApp()
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help("Quit Switch")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 345)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.92)
            }
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            viewModel.refreshAll()
        }
    }
}
