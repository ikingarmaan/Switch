import SwiftUI
import AppKit

public final class DockDoorCardState: ObservableObject {
    @Published public var isHovered: Bool = false
    public init() {}
}

public struct DockDoorPreviewRootView: View {
    @ObservedObject private var service = DockDoorService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: App Icon & App Title & Actions
            HStack(spacing: 8) {
                if let icon = service.currentHoveredIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                
                Text(service.currentHoveredApp ?? "Windows")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("(\(service.currentWindows.count))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                // Quick "New Window" action
                if let first = service.currentWindows.first {
                    Button(action: {
                        service.openNewWindow(for: first)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("New")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open New Window (⌘N)")
                }
            }
            .padding(.horizontal, 4)
            
            // Window Preview Cards Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(service.currentWindows) { win in
                        DockDoorCardView(
                            window: win,
                            cardSize: service.cardSize,
                            showActionButtons: service.showActionButtons,
                            onFocus: {
                                service.focusWindow(win)
                            },
                            onClose: {
                                service.closeWindow(win)
                            },
                            onMinimize: {
                                service.minimizeWindow(win)
                            },
                            onZoom: {
                                service.zoomWindow(win)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.14).opacity(0.88))
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}

public struct DockDoorCardView: View {
    let window: DockDoorWindowInfo
    let cardSize: DockDoorCardSize
    let showActionButtons: Bool
    let onFocus: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onZoom: () -> Void
    
    @StateObject private var state = DockDoorCardState()
    
    public init(
        window: DockDoorWindowInfo,
        cardSize: DockDoorCardSize,
        showActionButtons: Bool,
        onFocus: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onMinimize: @escaping () -> Void,
        onZoom: @escaping () -> Void
    ) {
        self.window = window
        self.cardSize = cardSize
        self.showActionButtons = showActionButtons
        self.onFocus = onFocus
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }
    
    public var body: some View {
        Button(action: onFocus) {
            VStack(alignment: .leading, spacing: 6) {
                // Window Title Header on Card
                HStack(spacing: 6) {
                    Text(window.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Quick Action Buttons (🔴 ✕ / 🟡 ─ / 🟢 ⤢)
                    if showActionButtons {
                        HStack(spacing: 5) {
                            // Zoom
                            Button(action: onZoom) {
                                Circle()
                                    .fill(Color.green.opacity(0.85))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 5, weight: .bold))
                                            .foregroundColor(.black.opacity(0.7))
                                            .opacity(state.isHovered ? 1.0 : 0.0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Zoom / Maximize")
                            
                            // Minimize
                            Button(action: onMinimize) {
                                Circle()
                                    .fill(Color.yellow.opacity(0.85))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Image(systemName: "minus")
                                            .font(.system(size: 5, weight: .bold))
                                            .foregroundColor(.black.opacity(0.7))
                                            .opacity(state.isHovered ? 1.0 : 0.0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Minimize Window")
                            
                            // Close Window
                            Button(action: onClose) {
                                Circle()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Image(systemName: "xmark")
                                            .font(.system(size: 5, weight: .bold))
                                            .foregroundColor(.black.opacity(0.7))
                                            .opacity(state.isHovered ? 1.0 : 0.0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Close Window")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                
                // Window Preview Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                    
                    if let thumb = window.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(6)
                            .padding(2)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.4))
                            Text(window.appName)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    if window.isMinimized {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("Minimized")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.2))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(4)
                                    .padding(6)
                            }
                        }
                    }
                }
                .frame(width: cardSize.width - 12, height: cardSize.height - 30)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(state.isHovered ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        state.isHovered ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.12),
                        lineWidth: state.isHovered ? 1.5 : 1
                    )
            )
            .scaleEffect(state.isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: state.isHovered)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.12)) {
                    state.isHovered = hover
                }
            }
        }
        .buttonStyle(.plain)
    }
}
