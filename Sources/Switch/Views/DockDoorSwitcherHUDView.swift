import SwiftUI
import AppKit

public struct DockDoorSwitcherHUDView: View {
    @ObservedObject private var service = DockDoorService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Top Header: Active Window Info & App Identity
            if let selected = service.selectedSwitcherWindow {
                HStack(spacing: 12) {
                    if let icon = selected.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(selected.appName)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            if selected.isMinimized {
                                Text("Minimized")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.yellow.opacity(0.25))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(selected.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Keyboard Shortcut Navigation Hints
                    HStack(spacing: 6) {
                        hintBadge(key: "⇥", label: "Next")
                        hintBadge(key: "⇧⇥", label: "Prev")
                        hintBadge(key: "W", label: "Close")
                        hintBadge(key: "Q", label: "Quit")
                        hintBadge(key: "Esc", label: "Cancel")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            
            // Carousel of Live Window Thumbnail Cards
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(service.switcherWindows.enumerated()), id: \.element.id) { index, win in
                            let isSelected = (index == service.switcherSelectedIndex)
                            
                            Button(action: {
                                service.selectWindow(at: index)
                                service.commitSwitcherSelection()
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Window Card Header
                                    HStack(spacing: 6) {
                                        if let icon = win.appIcon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 14, height: 14)
                                        }
                                        
                                        Text(win.title)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        // Quick Close Button on Card
                                        Button(action: {
                                            service.closeWindow(win)
                                        }) {
                                            Circle()
                                                .fill(Color.red.opacity(0.85))
                                                .frame(width: 12, height: 12)
                                                .overlay(
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 6, weight: .bold))
                                                        .foregroundColor(.black.opacity(0.8))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .help("Close Window (W)")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.top, 8)
                                    
                                    // Live Window Thumbnail Image
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.black.opacity(0.45))
                                        
                                        if let thumb = win.thumbnail {
                                            Image(nsImage: thumb)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .cornerRadius(8)
                                                .padding(3)
                                        } else {
                                            VStack(spacing: 6) {
                                                Image(systemName: "macwindow")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.white.opacity(0.35))
                                                Text(win.appName)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                        }
                                    }
                                    .frame(width: 260, height: 165)
                                    .padding(.horizontal, 6)
                                    .padding(.bottom, 8)
                                }
                                .frame(width: 272, height: 212)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            isSelected ? Color(red: 0.35, green: 0.75, blue: 0.98) : Color.white.opacity(0.12),
                                            lineWidth: isSelected ? 2.5 : 1
                                        )
                                )
                                .shadow(
                                    color: isSelected ? Color(red: 0.35, green: 0.75, blue: 0.98).opacity(0.4) : Color.black.opacity(0.3),
                                    radius: isSelected ? 16 : 8,
                                    x: 0,
                                    y: isSelected ? 6 : 3
                                )
                                .scaleEffect(isSelected ? 1.04 : 0.98)
                                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
                            }
                            .buttonStyle(.plain)
                            .id(win.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: service.switcherSelectedIndex) { newIndex in
                    if newIndex >= 0 && newIndex < service.switcherWindows.count {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(service.switcherWindows[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
            
            // Footer: Count indicator & Release key message
            HStack {
                Text("\(service.switcherSelectedIndex + 1) of \(service.switcherWindows.count) open windows")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text("Release modifier key to switch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.11).opacity(0.92))
                
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 15)
        .frame(minWidth: 420, maxWidth: 960)
    }
    
    private func hintBadge(key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.18))
                .cornerRadius(4)
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08))
        .cornerRadius(6)
    }
}
