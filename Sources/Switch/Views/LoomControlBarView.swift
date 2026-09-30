import SwiftUI
import AppKit

final class LoomControlBarState: ObservableObject {
    @Published var isHovered: Bool = false
}

public struct LoomControlBarView: View {
    @ObservedObject var service: LoomRecorderService
    @StateObject private var state = LoomControlBarState()
    
    public init(service: LoomRecorderService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Drag Handle
            HStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 2.5) {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 3, height: 3)
                    }
                }
            }
            .padding(.leading, 6)
            
            // Primary Action: Record / Stop
            if service.isRecording {
                // STOP RECORDING BUTTON + TIMER
                Button(action: {
                    service.stopRecording(discard: false)
                }) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.25))
                                .frame(width: 28, height: 28)
                            
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(Color(red: 1.0, green: 0.25, blue: 0.25))
                                .frame(width: 12, height: 12)
                        }
                        
                        Text(service.formattedDuration)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Stop Recording & Review")
                
                // PAUSE / RESUME BUTTON
                Button(action: {
                    if service.isPaused {
                        service.resumeRecording()
                    } else {
                        service.pauseRecording()
                    }
                }) {
                    Image(systemName: service.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(service.isPaused ? .orange : .white.opacity(0.9))
                        .frame(width: 30, height: 30)
                        .background(service.isPaused ? Color.orange.opacity(0.25) : Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(service.isPaused ? "Resume Recording" : "Pause Recording")
                
                // RESTART BUTTON
                Button(action: {
                    service.restartRecording()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Restart Recording (Discard current take)")
                
                // TRASH / CANCEL BUTTON
                Button(action: {
                    service.stopRecording(discard: true)
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel & Delete Recording")
                
            } else {
                // START RECORDING BUTTON
                Button(action: {
                    service.triggerRecordingToggle()
                }) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 26, height: 26)
                            Circle()
                                .fill(Color(red: 1.0, green: 0.25, blue: 0.25))
                                .frame(width: 13, height: 13)
                        }
                        
                        Text("Record")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Start Loom Recording (3s countdown)")
            }
            
            Divider()
                .frame(height: 18)
                .background(Color.white.opacity(0.2))
            
            // Microphone Toggle
            Button(action: {
                service.isMicEnabled.toggle()
            }) {
                Image(systemName: service.isMicEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(service.isMicEnabled ? Color(red: 0.38, green: 0.85, blue: 0.45) : Color.red.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(service.isMicEnabled ? "Microphone On (Click to mute)" : "Microphone Off (Click to enable)")
            
            // Camera Bubble Toggle
            Button(action: {
                service.isCameraVisible.toggle()
            }) {
                Image(systemName: service.isCameraVisible ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                .foregroundColor(service.isCameraVisible ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.gray)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(service.isCameraVisible ? "Hide Camera Bubble" : "Show Camera Bubble")
            
            // Presenter Mode Toggle
            Button(action: {
                withAnimation(.spring()) {
                    service.togglePresenterMode()
                }
            }) {
                Image(systemName: service.isPresenterMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(service.isPresenterMode ? Color(red: 1.0, green: 0.72, blue: 0.20) : Color.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(service.isPresenterMode ? "Exit Presenter Mode" : "Presenter Mode (Expand Camera)")
            
            // Reaction Emojis Menu
            Menu {
                ForEach(["🎉 Party", "👍 Thumbs Up", "❤️ Heart", "🔥 Fire", "💡 Idea", "🚀 Rocket"], id: \.self) { item in
                    let emoji = String(item.prefix(2)).trimmingCharacters(in: .whitespaces)
                    Button(action: {
                        service.triggerReaction(emoji)
                    }) {
                        Text(item)
                    }
                }
            } label: {
                Text("🎉")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Send Live Reaction Burst")
            
            // Open Recordings Folder
            Button(action: {
                service.openRecordingsFolder()
            }) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open Recordings Folder in Finder")
            
            // Close Loom Session
            Button(action: {
                service.stopSession()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Loom Recorder")
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
                
                WindowDraggableView()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        )
        .frame(height: 56)
    }
}
