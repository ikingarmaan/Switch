import Cocoa
import SwiftUI
import IOKit
import IOKit.pwr_mgt
import IOKit.hid
import Combine

public extension Notification.Name {
    static let macDuoStateDidChange = Notification.Name("SwitchMacDuoStateDidChange")
    static let macDuoAngleDidChange = Notification.Name("SwitchMacDuoAngleDidChange")
}

// MARK: - Mac Duo Visual Themes

public enum MacDuoStyle: String, CaseIterable, Identifiable, Sendable {
    case perspectiveOLED = "perspectiveOLED"
    case frostedGlass = "frostedGlass"
    case cyberpunk = "cyberpunk"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .perspectiveOLED: return "3D OLED Duo Fold"
        case .frostedGlass: return "Frosted Glass Book"
        case .cyberpunk: return "Cyberpunk Horizon"
        }
    }
    
    public var iconName: String {
        switch self {
        case .perspectiveOLED: return "laptopcomputer.and.ipad"
        case .frostedGlass: return "book.closed.fill"
        case .cyberpunk: return "waveform.path.ecg"
        }
    }
    
    public var description: String {
        switch self {
        case .perspectiveOLED: return "Realistic hardware folding screen with dynamic crease shadow & perspective"
        case .frostedGlass: return "Dual frosted glass panels with book spine curvature"
        case .cyberpunk: return "Futuristic obsidian panels with neon crease glow"
        }
    }
}

// MARK: - Dedicated Fullscreen Overlay Panel

public final class MacDuoOverlayPanel: NSPanel {
    public init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.sharingType = .none
    }
    
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

// MARK: - MacDuo Service Singleton

public final class MacDuoService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = MacDuoService()
    
    // Published State
    @Published public private(set) var isEnabled: Bool = false
    @Published public var currentAngle: Double = 180.0
    @Published public private(set) var isClamshellClosed: Bool = false
    @Published public private(set) var isAnimating: Bool = false
    @Published public var selectedStyle: MacDuoStyle = .perspectiveOLED
    @Published public var soundEnabled: Bool = true
    @Published public private(set) var isSimulatorOpen: Bool = false
    @Published public private(set) var wallpaperImage: NSImage?
    
    // Internal Windows & Watchers
    private var overlayPanel: MacDuoOverlayPanel?
    private var simulatorWindow: NSWindow?
    private var clamshellTimer: Timer?
    private var animationTimer: Timer?
    private var hidManager: IOHIDManager?
    private var lastAudioMilestone: Int = 180
    private var cancellables = Set<AnyCancellable>()
    
    private let keyEnabled = "switch.macDuo.enabled"
    private let keyStyle = "switch.macDuo.style"
    private let keySound = "switch.macDuo.sound"
    
    public var statusSubtitle: String {
        if !isEnabled {
            return "Off"
        }
        if currentAngle >= 179.0 {
            return "180° Flat"
        }
        return "\(Int(currentAngle))° Fold"
    }
    
    private override init() {
        super.init()
        loadPreferences()
        loadActiveWallpaper()
        setupNotificationObservers()
        setupLidAngleHIDSensor()
    }
    
    // MARK: - Preferences
    
    private func loadPreferences() {
        if let styleRaw = UserDefaults.standard.string(forKey: keyStyle),
           let style = MacDuoStyle(rawValue: styleRaw) {
            self.selectedStyle = style
        }
        if UserDefaults.standard.object(forKey: keySound) != nil {
            self.soundEnabled = UserDefaults.standard.bool(forKey: keySound)
        } else {
            self.soundEnabled = true
        }
    }
    
    public func setStyle(_ style: MacDuoStyle) {
        self.selectedStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: keyStyle)
    }
    
    public func setSoundEnabled(_ enabled: Bool) {
        self.soundEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: keySound)
    }
    
    // MARK: - Wallpaper Loading
    
    public func loadActiveWallpaper() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var image: NSImage? = nil
            if let screen = NSScreen.main,
               let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                image = NSImage(contentsOf: url)
            }
            if image == nil {
                // Fallback default high-res gradient
                image = self.createFallbackWallpaperImage()
            }
            DispatchQueue.main.async {
                self.wallpaperImage = image
            }
        }
    }
    
    private func createFallbackWallpaperImage() -> NSImage {
        let size = NSSize(width: 1440, height: 900)
        let img = NSImage(size: size)
        img.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(red: 0.10, green: 0.12, blue: 0.28, alpha: 1.0),
            NSColor(red: 0.18, green: 0.22, blue: 0.44, alpha: 1.0),
            NSColor(red: 0.25, green: 0.15, blue: 0.35, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        img.unlockFocus()
        return img
    }
    
    // MARK: - Toggle / Enable State
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setEnabled(_ enable: Bool) {
        guard enable != isEnabled else { return }
        isEnabled = enable
        UserDefaults.standard.set(enable, forKey: keyEnabled)
        
        if enable {
            loadActiveWallpaper()
            startClamshellMonitoring()
            // Reset to flat
            currentAngle = 180.0
            updateOverlayVisibility()
        } else {
            stopClamshellMonitoring()
            closeSimulatorWindow()
            currentAngle = 180.0
            hideOverlay()
        }
        
        NotificationCenter.default.post(name: .macDuoStateDidChange, object: enable)
    }
    
    // MARK: - Overlay Management
    
    private func ensureOverlayPanel() -> MacDuoOverlayPanel {
        if let existing = overlayPanel {
            return existing
        }
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let panel = MacDuoOverlayPanel(screen: screen)
        let hostingView = NSHostingView(rootView: MacDuoOverlayHostingView(service: self))
        hostingView.frame = screen.frame
        panel.contentView = hostingView
        overlayPanel = panel
        return panel
    }
    
    public func updateOverlayVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isEnabled {
                self.hideOverlay()
                return
            }
            
            // Show overlay when angle is folded (< 179°) or simulator is active
            if self.currentAngle < 179.0 || self.isSimulatorOpen || self.isAnimating {
                let panel = self.ensureOverlayPanel()
                if let screen = NSScreen.main {
                    panel.setFrame(screen.frame, display: true)
                }
                panel.orderFrontRegardless()
            } else {
                self.hideOverlay()
            }
        }
    }
    
    public func hideOverlay() {
        overlayPanel?.orderOut(nil)
    }
    
    // MARK: - Angle Control & Sound Feedback
    
    public func setAngle(_ angle: Double, animated: Bool = false) {
        let clamped = max(0.0, min(180.0, angle))
        
        if animated {
            animateAngle(to: clamped, duration: 0.35)
        } else {
            self.currentAngle = clamped
            checkAudioMilestone(for: clamped)
            updateOverlayVisibility()
            NotificationCenter.default.post(name: .macDuoAngleDidChange, object: clamped)
        }
    }
    
    private func animateAngle(to target: Double, duration: Double, completion: (() -> Void)? = nil) {
        animationTimer?.invalidate()
        isAnimating = true
        updateOverlayVisibility()
        
        let startAngle = currentAngle
        let delta = target - startAngle
        let steps = 30
        let stepDuration = duration / Double(steps)
        var currentStep = 0
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            currentStep += 1
            let progress = Double(currentStep) / Double(steps)
            // Smooth easeInOut curve
            let eased = progress < 0.5 ? 2.0 * progress * progress : 1.0 - pow(-2.0 * progress + 2.0, 2.0) / 2.0
            let newAngle = startAngle + (delta * eased)
            self.currentAngle = newAngle
            self.checkAudioMilestone(for: newAngle)
            NotificationCenter.default.post(name: .macDuoAngleDidChange, object: newAngle)
            
            if currentStep >= steps {
                timer.invalidate()
                self.currentAngle = target
                self.isAnimating = false
                self.updateOverlayVisibility()
                completion?()
            }
        }
    }
    
    private func checkAudioMilestone(for angle: Double) {
        guard soundEnabled else { return }
        let intAngle = Int(angle)
        let milestones = [15, 45, 90, 135, 175]
        
        for m in milestones {
            if abs(intAngle - m) <= 2 && abs(lastAudioMilestone - m) > 5 {
                lastAudioMilestone = m
                playHapticAndSound()
                break
            }
        }
    }
    
    public func playHapticAndSound() {
        guard soundEnabled else { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            NSSound(named: "Tink")?.play()
        }
    }
    
    // MARK: - Automated Test Fold Animation
    
    public func testFoldAnimation() {
        guard isEnabled else {
            setEnabled(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.testFoldAnimation()
            }
            return
        }
        
        // Stage 1: Smoothly fold from current angle to 35°
        animateAngle(to: 35.0, duration: 1.0) { [weak self] in
            guard let self = self else { return }
            self.playHapticAndSound()
            // Hold folded position for a moment to admire the 3D perspective
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                // Stage 2: Smoothly unfold back to 180°
                self?.animateAngle(to: 180.0, duration: 1.1) { [weak self] in
                    self?.playHapticAndSound()
                }
            }
        }
    }
    
    // MARK: - Clamshell & Sleep Monitoring
    
    private func setupNotificationObservers() {
        // Workspace Sleep / Wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }
    
    private func startClamshellMonitoring() {
        clamshellTimer?.invalidate()
        clamshellTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollClamshellState()
        }
    }
    
    private func stopClamshellMonitoring() {
        clamshellTimer?.invalidate()
        clamshellTimer = nil
    }
    
    private func pollClamshellState() {
        let isClosed = queryAppleClamshellState()
        if isClosed != isClamshellClosed {
            isClamshellClosed = isClosed
            if isClosed {
                // Lid closed: trigger fold down
                animateAngle(to: 0.0, duration: 0.7)
            } else {
                // Lid opened: trigger unfold up
                animateAngle(to: 180.0, duration: 0.7)
            }
        }
    }
    
    private func queryAppleClamshellState() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        
        if let prop = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) {
            let val = prop.takeRetainedValue()
            if let boolVal = val as? Bool {
                return boolVal
            }
            if let numVal = val as? NSNumber {
                return numVal.boolValue
            }
        }
        return false
    }
    
    @objc private func handleWillSleep(_ note: Notification) {
        guard isEnabled else { return }
        animateAngle(to: 0.0, duration: 0.5)
    }
    
    @objc private func handleDidWake(_ note: Notification) {
        guard isEnabled else { return }
        animateAngle(to: 180.0, duration: 0.8)
    }
    
    @objc private func handleScreensDidSleep(_ note: Notification) {
        guard isEnabled else { return }
        animateAngle(to: 0.0, duration: 0.5)
    }
    
    @objc private func handleScreensDidWake(_ note: Notification) {
        guard isEnabled else { return }
        animateAngle(to: 180.0, duration: 0.8)
    }
    
    // MARK: - Hardware LID Angle HID Sensor (For supported hardware)
    
    private func setupLidAngleHIDSensor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0x0020, // Sensor Page
            kIOHIDDeviceUsageKey as String: 0x008A      // Hinge / Lid Angle Sensor
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let service = Unmanaged<MacDuoService>.fromOpaque(context).takeUnretainedValue()
            guard service.isEnabled && !service.isAnimating else { return }
            
            let doubleVal = IOHIDValueGetScaledValue(value, IOHIDValueScaleType(kIOHIDValueScaleTypePhysical))
            if doubleVal >= 0 && doubleVal <= 180 {
                DispatchQueue.main.async {
                    service.setAngle(doubleVal, animated: false)
                }
            }
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openStatus == kIOReturnSuccess {
            self.hidManager = manager
        }
    }
    
    // MARK: - Interactive Simulator Window
    
    public func openSimulatorWindow() {
        if !isEnabled {
            setEnabled(true)
        }
        
        if let win = simulatorWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isSimulatorOpen = true
            updateOverlayVisibility()
            return
        }
        
        let screen = NSScreen.main ?? NSScreen()
        let width: CGFloat = 340
        let height: CGFloat = 430
        let x = screen.visibleFrame.maxX - width - 24
        let y = screen.visibleFrame.maxY - height - 48
        
        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "MacBook Duo • Interactive Fold Simulator"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        
        let hostingView = NSHostingView(rootView: MacDuoSimulatorView(service: self))
        win.contentView = hostingView
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.isSimulatorOpen = false
            self?.updateOverlayVisibility()
        }
        
        self.simulatorWindow = win
        self.isSimulatorOpen = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateOverlayVisibility()
    }
    
    public func closeSimulatorWindow() {
        simulatorWindow?.close()
        isSimulatorOpen = false
        updateOverlayVisibility()
    }
    
    public func toggleSimulatorWindow() {
        if isSimulatorOpen {
            closeSimulatorWindow()
        } else {
            openSimulatorWindow()
        }
    }
}

// MARK: - Fullscreen 3D Folding Overlay View

public struct MacDuoOverlayHostingView: View {
    @ObservedObject public var service: MacDuoService
    
    public init(service: MacDuoService) {
        self.service = service
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let angle = service.currentAngle
            // Progress: 0.0 (unfolded/180°) -> 1.0 (folded/0°)
            let progress = CGFloat(max(0.0, min(1.0, (180.0 - angle) / 180.0)))
            
            // Angles for 3D rotation
            // Upper panel rotates backward away from viewer
            let upperPitch = -Double(180.0 - angle) * 0.44
            // Lower panel rotates slightly forward to simulate laptop base
            let lowerPitch = Double(180.0 - angle) * 0.12
            
            ZStack {
                // Background dark ambient scrim when folded
                Color.black
                    .opacity(Double(progress) * 0.88)
                    .edgesIgnoringSafeArea(.all)
                
                // The 3D Folding Screen Assembly
                VStack(spacing: 0) {
                    // TOP HALF SCREEN (Bends backward into 3D)
                    UpperFoldPanel(service: service, width: w, height: h / 2, progress: progress)
                        .frame(width: w, height: h / 2)
                        .rotation3DEffect(
                            .degrees(upperPitch),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .bottom,
                            perspective: 0.65
                        )
                        .clipped()
                    
                    // HINGE / CREASE SPINE
                    HingeSpineView(service: service, width: w, progress: progress)
                    
                    // BOTTOM HALF SCREEN (Bends forward into 3D)
                    LowerFoldPanel(service: service, width: w, height: h / 2, progress: progress)
                        .frame(width: w, height: h / 2)
                        .rotation3DEffect(
                            .degrees(lowerPitch),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .top,
                            perspective: 0.65
                        )
                        .clipped()
                }
                .frame(width: w, height: h)
                
                // Top Center Minimal HUD Badge
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer.and.ipad")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(styleAccentColor)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MacBook Duo")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("\(Int(service.currentAngle))° • \(statusTitle)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        
                        Spacer()
                            .frame(width: 8)
                        
                        Button(action: {
                            service.testFoldAnimation()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                Text("Test Fold")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(6)
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            service.setAngle(180.0, animated: true)
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .padding(5)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Unfold to 180° Flat")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.75))
                            .overlay(
                                Capsule()
                                    .strokeBorder(styleAccentColor.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    )
                    .padding(.top, 24)
                    .opacity(progress > 0.05 ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: progress > 0.05)
                    
                    Spacer()
                }
            }
        }
    }
    
    private var styleAccentColor: Color {
        switch service.selectedStyle {
        case .perspectiveOLED:
            return Color(red: 0.20, green: 0.65, blue: 1.0)
        case .frostedGlass:
            return Color(red: 0.55, green: 0.85, blue: 1.0)
        case .cyberpunk:
            return Color(red: 0.95, green: 0.20, blue: 0.70)
        }
    }
    
    private var statusTitle: String {
        let angle = service.currentAngle
        if angle >= 175 { return "Flat 180°" }
        if angle >= 120 { return "Laptop Mode" }
        if angle >= 75 { return "Right Angle 90°" }
        if angle >= 30 { return "Tent Mode" }
        return "Folded Clamshell"
    }
}

// MARK: - Upper Panel Subview

private struct UpperFoldPanel: View {
    @ObservedObject var service: MacDuoService
    let width: CGFloat
    let height: CGFloat
    let progress: CGFloat
    
    var body: some View {
        ZStack(alignment: .top) {
            // Screen Background Image
            if let wallpaper = service.wallpaperImage {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height * 2, alignment: .top)
                    .clipped()
            } else {
                Color(red: 0.12, green: 0.15, blue: 0.28)
            }
            
            // Simulated macOS Top Menu Bar
            HStack(spacing: 12) {
                Image(systemName: "applelogo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Switch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text("File")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text("Edit")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text("View")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text("Window")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "battery.100")
                        .font(.system(size: 11))
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                    Text("MacBook Duo")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.25))
            
            // Dynamic Perspective Shading & Crease Shadow
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(Double(progress) * 0.45),
                    Color.black.opacity(Double(progress) * 0.92)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Stylistic Overlays
            if service.selectedStyle == .frostedGlass {
                Rectangle()
                    .fill(Color.white.opacity(Double(progress) * 0.12))
                    .blendMode(.overlay)
            } else if service.selectedStyle == .cyberpunk {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(red: 0.95, green: 0.20, blue: 0.70).opacity(Double(progress) * 0.35)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: width, height: height)
        .blur(radius: progress * 4.0)
    }
}

// MARK: - Lower Panel Subview

private struct LowerFoldPanel: View {
    @ObservedObject var service: MacDuoService
    let width: CGFloat
    let height: CGFloat
    let progress: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Screen Background Image (Lower half)
            if let wallpaper = service.wallpaperImage {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height * 2, alignment: .bottom)
                    .clipped()
            } else {
                Color(red: 0.12, green: 0.15, blue: 0.28)
            }
            
            // Dynamic Crease Shadow cast from upper panel
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(Double(progress) * 0.85),
                    Color.black.opacity(Double(progress) * 0.25),
                    Color.clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Simulated Dock Area
            HStack(spacing: 12) {
                ForEach(["finder", "safari", "terminal", "gear", "note.text"], id: \.self) { icon in
                    Image(systemName: icon == "finder" ? "square.grid.2x2.fill" : icon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .padding(.bottom, 12)
            .opacity(1.0 - Double(progress) * 0.5)
            
            // Stylistic Overlays
            if service.selectedStyle == .cyberpunk {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.70, blue: 0.95).opacity(Double(progress) * 0.3),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Hinge Spine Crease View

private struct HingeSpineView: View {
    @ObservedObject var service: MacDuoService
    let width: CGFloat
    let progress: CGFloat
    
    var body: some View {
        ZStack {
            // Deep crease valley
            Rectangle()
                .fill(Color.black.opacity(Double(progress) * 0.95))
                .frame(width: width, height: max(1, progress * 4))
            
            // Specular reflection line simulating curved glass/metal
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            spineAccent.opacity(0.1),
                            spineAccent.opacity(Double(progress) * 0.85),
                            spineAccent.opacity(0.1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 1.5)
        }
        .frame(width: width, height: max(2, progress * 6))
    }
    
    private var spineAccent: Color {
        switch service.selectedStyle {
        case .perspectiveOLED:
            return Color.white.opacity(0.7)
        case .frostedGlass:
            return Color(red: 0.6, green: 0.85, blue: 1.0)
        case .cyberpunk:
            return Color(red: 0.95, green: 0.25, blue: 0.75)
        }
    }
}

// MARK: - Interactive Simulator Window View

public struct MacDuoSimulatorView: View {
    @ObservedObject public var service: MacDuoService
    
    public init(service: MacDuoService) {
        self.service = service
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer.and.ipad")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacBook Duo")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Folding Screen Simulator")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    service.closeSimulatorWindow()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            
            Divider()
            
            // Angle Meter & Graphic
            VStack(spacing: 8) {
                HStack {
                    Text("LID FOLD ANGLE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(service.currentAngle))°")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                }
                
                // Interactive Slider
                Slider(
                    value: Binding<Double>(
                        get: { service.currentAngle },
                        set: { service.setAngle($0, animated: false) }
                    ),
                    in: 0.0...180.0,
                    step: 1.0
                )
                .accentColor(Color(red: 0.25, green: 0.65, blue: 1.0))
                
                HStack {
                    Text("0° (Closed)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("90° (Half)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("180° (Flat)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(10)
            
            // Preset Buttons
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK ANGLE PRESETS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    PresetPill(title: "180° Flat", angle: 180.0, service: service)
                    PresetPill(title: "135° Laptop", angle: 135.0, service: service)
                    PresetPill(title: "90° Book", angle: 90.0, service: service)
                    PresetPill(title: "45° Tent", angle: 45.0, service: service)
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    service.testFoldAnimation()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Test Duo Fold Animation")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.20, green: 0.60, blue: 1.0))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Style Picker & Audio Settings
            VStack(alignment: .leading, spacing: 8) {
                Text("FOLD THEME")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    ForEach(MacDuoStyle.allCases) { style in
                        Button(action: {
                            service.setStyle(style)
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: style.iconName)
                                    .font(.system(size: 12))
                                Text(style.title)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                service.selectedStyle == style ?
                                Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.2) :
                                Color(NSColor.controlBackgroundColor).opacity(0.4)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        service.selectedStyle == style ?
                                        Color(red: 0.25, green: 0.65, blue: 1.0) :
                                        Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Toggle(isOn: Binding<Bool>(
                    get: { service.soundEnabled },
                    set: { service.setSoundEnabled($0) }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: service.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 11))
                        Text("Play Hinge Sound & Haptics")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.top, 2)
            }
            
            Spacer()
        }
        .padding(16)
        .frame(width: 340, height: 430)
    }
}

private struct PresetPill: View {
    let title: String
    let angle: Double
    @ObservedObject var service: MacDuoService
    
    var body: some View {
        Button(action: {
            service.setAngle(angle, animated: true)
        }) {
            Text(title)
                .font(.system(size: 10, weight: abs(service.currentAngle - angle) < 2 ? .bold : .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    abs(service.currentAngle - angle) < 2 ?
                    Color(red: 0.25, green: 0.65, blue: 1.0).opacity(0.25) :
                    Color(NSColor.controlBackgroundColor).opacity(0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            abs(service.currentAngle - angle) < 2 ?
                            Color(red: 0.25, green: 0.65, blue: 1.0) :
                            Color.clear,
                            lineWidth: 1
                        )
                )
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
