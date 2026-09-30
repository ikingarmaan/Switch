import SwiftUI
import AVKit
import AppKit

final class LoomReviewModalState: ObservableObject {
    @Published var copiedFeedback: Bool = false
    @Published var fileSizeString: String = ""
    
    func setCopied() {
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.copiedFeedback = false
        }
    }
    
    func updateFileSize(for url: URL?) {
        guard let url = url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            fileSizeString = ""
            return
        }
        let mb = Double(size) / (1024 * 1024)
        if mb >= 1.0 {
            fileSizeString = String(format: "%.1f MB", mb)
        } else {
            let kb = Double(size) / 1024
            fileSizeString = String(format: "%.0f KB", kb)
        }
    }
}

public struct LoomReviewModalView: View {
    @ObservedObject var service: LoomRecorderService
    @StateObject private var state = LoomReviewModalState()
    
    public init(service: LoomRecorderService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.35, green: 0.85, blue: 0.55))
                    
                    Text("Recording Ready!")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    if !state.fileSizeString.isEmpty {
                        Text("• \(state.fileSizeString)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                Button(action: {
                    service.hideReviewModal()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close Review")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            // Video Player Area
            ZStack {
                Color.black
                
                if let url = service.lastRecordingURL {
                    LoomVideoPlayerView(url: url)
                } else {
                    Text("No Video Available")
                        .foregroundColor(.gray)
                }
            }
            .frame(height: 270)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                // Delete
                Button(action: {
                    service.deleteLastRecording()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Delete")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Delete this recording")
                
                Spacer()
                
                // Open in QuickTime
                Button(action: {
                    service.openLastRecordingInQuickTime()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 12))
                        Text("QuickTime")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Open in QuickTime Player")
                
                // Reveal in Finder
                Button(action: {
                    service.revealLastRecordingInFinder()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                        Text("Finder")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Reveal file in Finder")
                
                // Primary: Copy Video File
                Button(action: {
                    service.copyLastRecordingToClipboard()
                    state.setCopied()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: state.copiedFeedback ? "checkmark" : "doc.on.doc.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(state.copiedFeedback ? "Copied!" : "Copy Video (⌘V)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.22, green: 0.55, blue: 0.98), Color(red: 0.12, green: 0.42, blue: 0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.blue.opacity(0.35), radius: 4)
                }
                .buttonStyle(.plain)
                .help("Copy video file to clipboard for instant ⌘V pasting")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.13, green: 0.14, blue: 0.18).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 20)
        )
        .frame(width: 520, height: 380)
        .onAppear {
            state.updateFileSize(for: service.lastRecordingURL)
        }
    }
}

// MARK: - AVPlayerView Representable

public struct LoomVideoPlayerView: NSViewRepresentable {
    let url: URL
    
    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        let player = AVPlayer(url: url)
        playerView.player = player
        player.play()
        return playerView
    }
    
    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Keeps the existing player active
    }
}
