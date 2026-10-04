import SwiftUI

public struct WisprFlowFloatingHUD: View {
    @ObservedObject private var service = WisprFlowService.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            // Left: Status Indicator / Live Visualizer
            if service.isListening {
                // Pulsing Red Mic Dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.6), lineWidth: 2)
                            .scaleEffect(service.audioLevels.max() ?? 0.2 > 0.3 ? 1.8 : 1.2)
                            .opacity(service.audioLevels.max() ?? 0.2 > 0.3 ? 0.0 : 0.8)
                            .animation(.easeOut(duration: 0.8).repeatForever(autoreverses: false), value: service.isListening)
                    )
                
                // 7-Bar Real-Time Audio Visualizer Waveform
                HStack(spacing: 3) {
                    ForEach(0..<service.audioLevels.count, id: \.self) { i in
                        let level = service.audioLevels[i]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.35, green: 0.78, blue: 0.98), Color(red: 0.65, green: 0.45, blue: 0.98)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 3.5, height: max(4, level * 28))
                            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.6), value: level)
                    }
                }
                .frame(height: 30)
                
                // Duration Counter
                Text(formattedDuration(service.recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    
            } else if service.isProcessing {
                // AI Sparkle Spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.75, green: 0.55, blue: 1.0)))
                    .scaleEffect(0.85)
                
                Text(service.statusMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.85, green: 0.75, blue: 1.0))
            } else {
                // Checkmark / Result state
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                
                Text(service.statusMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Language Badge
            Text(service.language.shortLabel)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12))
                .foregroundColor(.white.opacity(0.9))
                .cornerRadius(6)
            
            // Action Buttons
            if service.isListening {
                // Stop & Transcribe Button
                Button(action: {
                    service.stopAndTranscribe()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 0.35, green: 0.78, blue: 0.98))
                }
                .buttonStyle(.plain)
                .help("Done Speaking (Auto-Paste)")
                
                // Cancel Button
                Button(action: {
                    service.cancelRecording()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 260, maxWidth: 320, minHeight: 46)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.14).opacity(0.85))
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.purple.opacity(0.2), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)
    }
    
    private func formattedDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
