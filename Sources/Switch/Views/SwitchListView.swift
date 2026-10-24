import SwiftUI

public struct SwitchListView: View {
    @ObservedObject private var viewModel = SwitchListViewModel.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Accent Notch
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.6))
                    .frame(width: 36, height: 3)
                    .padding(.top, 4)
                    .padding(.bottom, 5)
                Spacer()
            }
            
            // Search Bar
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(viewModel.searchText.isEmpty ? Color.gray.opacity(0.8) : Color(red: 0.28, green: 0.76, blue: 0.52))
                
                TextField("Search switches...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(.white)
                    .onSubmit {
                        if let firstMatch = viewModel.visibleSwitches.first {
                            if firstMatch.isActionOnly {
                                viewModel.triggerAction(type: firstMatch.type)
                            } else {
                                viewModel.toggleSwitch(item: firstMatch, newValue: !firstMatch.isOn)
                            }
                        }
                    }
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color.gray.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                } else {
                    Text("⌘⇧Z")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.gray.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(3)
                        .help("Global shortcut: Command+Shift+Z")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            
            // Switch List
            ScrollView(showsIndicators: false) {
                if viewModel.visibleSwitches.isEmpty && !viewModel.searchText.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 22))
                            .foregroundColor(Color.gray.opacity(0.6))
                            .padding(.top, 24)
                        Text("No switches match \"\(viewModel.searchText)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.8))
                        Button("Clear Search") {
                            viewModel.searchText = ""
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity)
                } else {
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
