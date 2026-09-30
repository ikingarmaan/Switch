import SwiftUI

public struct LoomCountdownView: View {
    @ObservedObject var service: LoomRecorderService
    
    public init(service: LoomRecorderService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        Button(action: {
            service.skipCountdownAndStart()
        }) {
            ZStack {
                // Background Circle
                Circle()
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.15).opacity(0.88))
                    .shadow(color: Color.black.opacity(0.5), radius: 16)
                
                // Outer Ring
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 5)
                
                // Progress Arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(service.countdownValue) / 3.0)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.35, blue: 0.35), Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                // Number
                VStack(spacing: 2) {
                    Text("\(max(1, service.countdownValue))")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("CLICK TO SKIP")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(1)
                }
            }
            .frame(width: 140, height: 140)
        }
        .buttonStyle(.plain)
    }
}
