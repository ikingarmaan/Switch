import Cocoa
import SwiftUI
import UserNotifications

public extension Notification.Name {
    static let timerStateDidChange = Notification.Name("SwitchTimerStateDidChange")
    static let timerTick = Notification.Name("SwitchTimerTick")
}

public final class CountdownTimerService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = CountdownTimerService()
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var remainingSeconds: Int = 1500 // Default 25 min
    @Published public var selectedDuration: Int = 1500
    
    public let presets: [(seconds: Int, label: String)] = [
        (60, "1m"),
        (300, "5m"),
        (600, "10m"),
        (900, "15m"),
        (1500, "25m"),
        (1800, "30m"),
        (2700, "45m"),
        (3600, "1h")
    ]
    
    private var timer: Timer?
    private var targetEndTime: Date?
    private var pausedRemainingSeconds: Int = 0
    private var floatingPillPanel: NSPanel?
    
    public var formattedRemainingTime: String {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    public var formattedSelectedDuration: String {
        let minutes = selectedDuration / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMin = minutes % 60
            return remMin > 0 ? "\(hours)h \(remMin)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
    
    public var progress: Double {
        guard selectedDuration > 0 else { return 0 }
        let elapsed = Double(selectedDuration - remainingSeconds)
        return min(max(elapsed / Double(selectedDuration), 0.0), 1.0)
    }
    
    override private init() {
        super.init()
        let saved = UserDefaults.standard.integer(forKey: "savedCountdownDuration")
        if saved > 0 {
            self.selectedDuration = saved
            self.remainingSeconds = saved
        }
    }
    
    public func setDuration(_ seconds: Int) {
        self.selectedDuration = seconds
        UserDefaults.standard.set(seconds, forKey: "savedCountdownDuration")
        if !isRunning {
            self.remainingSeconds = seconds
        }
        NotificationCenter.default.post(name: .timerStateDidChange, object: nil)
    }
    
    public func setEnabled(_ enable: Bool) {
        if enable {
            start()
        } else {
            stop()
        }
    }
    
    public func start(duration: Int? = nil) {
        if let d = duration {
            setDuration(d)
        }
        
        self.remainingSeconds = selectedDuration
        self.targetEndTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        self.isRunning = true
        self.isPaused = false
        
        startTimerLoop()
        DispatchQueue.main.async { [weak self] in
            self?.showFloatingPill()
        }
        
        NotificationCenter.default.post(name: .timerStateDidChange, object: true)
        NotificationCenter.default.post(name: .timerTick, object: formattedRemainingTime)
    }
    
    public func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        pausedRemainingSeconds = remainingSeconds
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.post(name: .timerStateDidChange, object: true)
    }
    
    public func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        targetEndTime = Date().addingTimeInterval(TimeInterval(pausedRemainingSeconds))
        startTimerLoop()
        NotificationCenter.default.post(name: .timerStateDidChange, object: true)
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        targetEndTime = nil
        remainingSeconds = selectedDuration
        
        DispatchQueue.main.async { [weak self] in
            self?.hideFloatingPill()
        }
        
        NotificationCenter.default.post(name: .timerStateDidChange, object: false)
        NotificationCenter.default.post(name: .timerTick, object: "")
    }
    
    private func startTimerLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }
    
    private func tick() {
        guard isRunning, !isPaused, let target = targetEndTime else { return }
        let diff = Int(ceil(target.timeIntervalSinceNow))
        
        if diff <= 0 {
            remainingSeconds = 0
            timerFinished()
        } else {
            remainingSeconds = diff
            NotificationCenter.default.post(name: .timerTick, object: formattedRemainingTime)
        }
    }
    
    private func timerFinished() {
        stop()
        
        // 1. Play chime sound
        playNotificationSound()
        
        // 2. Show native system alert & notification
        showFinishedAlert()
    }
    
    private func playNotificationSound() {
        let soundNames = ["Glass", "Ping", "Hero", "Blow"]
        for name in soundNames {
            if let sound = NSSound(named: name) {
                sound.play()
                return
            }
        }
        NSSound.beep()
    }
    
    private func showFinishedAlert() {
        let alert = NSAlert()
        alert.messageText = "⏰ Time's Up!"
        alert.informativeText = "Your countdown timer for \(formattedSelectedDuration) has finished."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Restart")
        
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        if alert.runModal() == .alertSecondButtonReturn {
            // Restart timer
            start()
        }
    }
    
    // MARK: - Floating Mini Timer Pill HUD
    
    private func setupPillPanelIfNeeded() {
        if floatingPillPanel != nil { return }
        
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let width: CGFloat = 190
        let height: CGFloat = 46
        let x = screenRect.maxX - width - 24
        let y = screenRect.maxY - height - 16
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: FloatingTimerPillView(service: self))
        panel.contentView = hostingView
        self.floatingPillPanel = panel
    }
    
    public func showFloatingPill() {
        setupPillPanelIfNeeded()
        floatingPillPanel?.orderFrontRegardless()
    }
    
    public func hideFloatingPill() {
        floatingPillPanel?.orderOut(nil)
    }
}

// MARK: - Floating Pill View

private struct FloatingTimerPillView: View {
    @ObservedObject var service: CountdownTimerService
    
    var body: some View {
        HStack(spacing: 8) {
            // Drag handle & Mini Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                
                Circle()
                    .trim(from: 0, to: CGFloat(service.progress))
                    .stroke(
                        Color(red: 0.28, green: 0.76, blue: 0.52),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(width: 20, height: 20)
            
            // Countdown Digits
            Text(service.formattedRemainingTime)
                .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer(minLength: 0)
            
            // Pause / Resume Button
            Button(action: {
                if service.isPaused {
                    service.resume()
                } else {
                    service.pause()
                }
            }) {
                Image(systemName: service.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help(service.isPaused ? "Resume" : "Pause")
            
            // Stop / Close Button
            Button(action: {
                service.stop()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Stop Timer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.9)
                WindowDragHandle()
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    service.isPaused
                        ? Color.orange.opacity(0.5)
                        : Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.5),
                    lineWidth: 1.2
                )
        )
    }
}

// MARK: - Drag Handle

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        return WindowDragNSView()
    }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
