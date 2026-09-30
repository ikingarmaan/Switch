import Cocoa
import SwiftUI
import CoreGraphics

public extension Notification.Name {
    static let googlyEyesStateDidChange = Notification.Name("SwitchGooglyEyesStateDidChange")
    static let googlyEyesEmotionDidChange = Notification.Name("SwitchGooglyEyesEmotionDidChange")
}

public enum EyeEmotion: String, CaseIterable, Sendable {
    case normal = "Normal"
    case happy = "Happy"
    case stressed = "Stressed"
    case dizzy = "Dizzy"
    case sleepy = "Sleepy"
    
    public var label: String {
        switch self {
        case .normal: return "Follows Cursor"
        case .happy: return "Happy 😊"
        case .stressed: return "Stressed 😫"
        case .dizzy: return "Dizzy 😵‍💫"
        case .sleepy: return "Dozing Off 😴"
        }
    }
}

public final class GooglyEyesService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = GooglyEyesService()
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var currentEmotion: EyeEmotion = .normal
    @Published public private(set) var continuousWorkSeconds: Int = 0
    @Published public private(set) var eyeScale: Double = 1.0
    
    private var statusItem: NSStatusItem?
    private var eyeView: GooglyEyesView?
    private var trackingTimer: Timer?
    private var secondTimer: Timer?
    private var randomBlinkTimer: Timer?
    private var clickMonitor: Any?
    private var lastMousePos: CGPoint = .zero
    private var lastMouseCheckTime: Date = Date()
    
    private var dizzyDurationRemaining: Double = 0
    private var happyDurationRemaining: Double = 0
    private var dizzyAngle: CGFloat = 0
    
    // Continuous shake tracking
    private var directionReversals: Int = 0
    private var consecutiveFastFrames: Int = 0
    private var lastVelocityX: CGFloat = 0
    private var lastVelocityY: CGFloat = 0
    private var lastReversalTime: Date = Date()
    
    private let lock = NSLock()
    private let keyEnabled = "switch.googlyEyesEnabled"
    private let keyEyeScale = "switch.googlyEyesScale"
    
    override private init() {
        super.init()
        let savedScale = UserDefaults.standard.double(forKey: keyEyeScale)
        if savedScale >= 0.4 && savedScale <= 2.0 {
            self.eyeScale = savedScale
        } else {
            self.eyeScale = 1.0
        }
        
        let saved = UserDefaults.standard.bool(forKey: keyEnabled)
        if saved {
            self.isEnabled = true
            DispatchQueue.main.async { [weak self] in
                self?.startGooglyEyes()
            }
        }
    }
    
    public func setEyeScale(_ scale: Double) {
        let clamped = max(0.4, min(1.8, scale))
        guard abs(self.eyeScale - clamped) > 0.005 else { return }
        
        self.eyeScale = clamped
        UserDefaults.standard.set(clamped, forKey: keyEyeScale)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
            self.updateEyeViewScale()
        }
    }
    
    @MainActor
    public func updateEyeViewScale() {
        guard isEnabled, let item = statusItem, let button = item.button else { return }
        let baseRadius: CGFloat = 10.0
        let eyeRadius: CGFloat = baseRadius * CGFloat(eyeScale)
        let spacing: CGFloat = eyeRadius * 0.45
        let requiredWidth: CGFloat = max(38.0, ceil((eyeRadius * 2.0 * 2.0) + spacing + 12.0))
        
        item.length = requiredWidth
        button.frame = NSRect(x: 0, y: 0, width: requiredWidth, height: button.frame.height)
        eyeView?.frame = button.bounds
        eyeView?.setEyeScale(CGFloat(eyeScale))
        eyeView?.needsDisplay = true
    }
    
    public func setManualEmotion(_ emotion: EyeEmotion) {
        self.currentEmotion = emotion
        eyeView?.setEmotion(emotion)
        NotificationCenter.default.post(name: .googlyEyesEmotionDidChange, object: emotion.label)
    }
    
    public func testBlink() {
        eyeView?.doubleBlink()
    }
    
    public func setEnabled(_ enable: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        guard enable != isEnabled else { return }
        isEnabled = enable
        UserDefaults.standard.set(enable, forKey: keyEnabled)
        
        DispatchQueue.main.async { [weak self] in
            if enable {
                self?.startGooglyEyes()
            } else {
                self?.stopGooglyEyes()
            }
            NotificationCenter.default.post(name: .googlyEyesStateDidChange, object: enable)
        }
    }
    
    // MARK: - Lifecycle
    
    @MainActor
    private func startGooglyEyes() {
        stopGooglyEyes()
        
        let baseRadius: CGFloat = 10.0
        let eyeRadius: CGFloat = baseRadius * CGFloat(eyeScale)
        let spacing: CGFloat = eyeRadius * 0.45
        let initialWidth: CGFloat = max(38.0, ceil((eyeRadius * 2.0 * 2.0) + spacing + 12.0))
        
        let item = NSStatusBar.system.statusItem(withLength: initialWidth)
        if let button = item.button {
            button.title = ""
            button.image = nil
            
            let eyes = GooglyEyesView(frame: button.bounds)
            eyes.autoresizingMask = [.width, .height]
            eyes.setEyeScale(CGFloat(eyeScale))
            button.addSubview(eyes)
            self.eyeView = eyes
            
            button.target = self
            button.action = #selector(statusItemClicked)
            button.toolTip = "Googly Eyes 👀"
        }
        self.statusItem = item
        
        // 1. Mouse tracking loop (30 fps)
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onTrackingTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.trackingTimer = timer
        
        // 2. Global mouse click monitor for blinking on click
        self.clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.eyeView?.blink()
            }
        }
        
        // 3. 1-second timer for work/idle tracking & emotional state machine
        self.secondTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onSecondTick()
            }
        }
        
        // 4. Natural blinking
        scheduleNextRandomBlink()
    }
    
    @MainActor
    private func stopGooglyEyes() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        
        secondTimer?.invalidate()
        secondTimer = nil
        
        randomBlinkTimer?.invalidate()
        randomBlinkTimer = nil
        
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        eyeView = nil
    }
    
    // MARK: - Ticks & State Machine
    
    @MainActor
    private func onTrackingTick() {
        let currentPos = NSEvent.mouseLocation
        let now = Date()
        let dt = max(now.timeIntervalSince(lastMouseCheckTime), 0.001)
        lastMouseCheckTime = now
        
        let dx = currentPos.x - lastMousePos.x
        let dy = currentPos.y - lastMousePos.y
        let dist = hypot(dx, dy)
        let speed = dist / dt
        
        // Continuous rapid shake detection:
        // Requires sustained high speed (> 2200 pt/s) AND at least 4 rapid direction reversals
        if speed > 2200 {
            let reversedX = (dx > 10 && lastVelocityX < -10) || (dx < -10 && lastVelocityX > 10)
            let reversedY = (dy > 10 && lastVelocityY < -10) || (dy < -10 && lastVelocityY > 10)
            
            if reversedX || reversedY {
                directionReversals += 1
                lastReversalTime = now
            }
            
            consecutiveFastFrames += 1
            lastVelocityX = dx
            lastVelocityY = dy
        } else {
            // Rapid decay if motion slows down or stops
            consecutiveFastFrames = max(consecutiveFastFrames - 2, 0)
        }
        
        // Reset reversals if no reversal occurred for over 0.45s
        if now.timeIntervalSince(lastReversalTime) > 0.45 {
            directionReversals = 0
        }
        
        // Only trigger Dizzy on true continuous back-and-forth rapid shaking:
        // Must have at least 14 consecutive fast frames (~0.5s) AND at least 4 direction reversals
        if consecutiveFastFrames >= 14 && directionReversals >= 4 && currentEmotion != .dizzy {
            triggerDizzy(duration: 2.8)
            directionReversals = 0
            consecutiveFastFrames = 0
        }
        
        // Update dizzy animation
        if dizzyDurationRemaining > 0 {
            dizzyDurationRemaining -= 1.0 / 30.0
            dizzyAngle += 0.45
            eyeView?.updateDizzyAngle(dizzyAngle)
            eyeView?.needsDisplay = true
        } else if happyDurationRemaining > 0 {
            happyDurationRemaining -= 1.0 / 30.0
            eyeView?.needsDisplay = true
        } else if currentPos != lastMousePos || (eyeView?.isBlinking ?? false) {
            eyeView?.needsDisplay = true
        }
        
        lastMousePos = currentPos
    }
    
    @MainActor
    private func onSecondTick() {
        // Query system idle time down to milliseconds
        let idleSec = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        
        if idleSec >= 180 {
            // Idle for 3+ minutes: user took a break! Reset continuous work fatigue
            continuousWorkSeconds = max(continuousWorkSeconds - 60, 0)
        } else if idleSec < 15 {
            // User is actively typing or moving mouse
            continuousWorkSeconds += 1
        }
        
        // Determine base emotion based on work & idle time
        var newEmotion: EyeEmotion = .normal
        
        if dizzyDurationRemaining > 0 {
            newEmotion = .dizzy
        } else if happyDurationRemaining > 0 {
            newEmotion = .happy
        } else if idleSec >= 75 {
            newEmotion = .sleepy
        } else if continuousWorkSeconds >= 1800 { // 30+ minutes of continuous active work
            newEmotion = .stressed
        } else {
            newEmotion = .normal
        }
        
        if newEmotion != currentEmotion {
            currentEmotion = newEmotion
            eyeView?.setEmotion(newEmotion)
            updateToolTip()
            NotificationCenter.default.post(name: .googlyEyesEmotionDidChange, object: newEmotion.label)
        }
    }
    
    @MainActor
    public func triggerDizzy(duration: Double = 2.8) {
        dizzyDurationRemaining = duration
        currentEmotion = .dizzy
        eyeView?.setEmotion(.dizzy)
        updateToolTip()
        NotificationCenter.default.post(name: .googlyEyesEmotionDidChange, object: EyeEmotion.dizzy.label)
    }
    
    @MainActor
    public func triggerHappy(duration: Double = 2.5) {
        happyDurationRemaining = duration
        currentEmotion = .happy
        eyeView?.setEmotion(.happy)
        updateToolTip()
        NotificationCenter.default.post(name: .googlyEyesEmotionDidChange, object: EyeEmotion.happy.label)
    }
    
    @MainActor
    private func updateToolTip() {
        switch currentEmotion {
        case .normal:
            statusItem?.button?.toolTip = "Googly Eyes 👀 (Active)"
        case .happy:
            statusItem?.button?.toolTip = "Googly Eyes: Happy! 😊"
        case .stressed:
            let mins = continuousWorkSeconds / 60
            statusItem?.button?.toolTip = "Googly Eyes: Stressed 😫 (\(mins)m continuous work — Take a short break!)"
        case .dizzy:
            statusItem?.button?.toolTip = "Googly Eyes: Dizzy! 😵‍💫"
        case .sleepy:
            statusItem?.button?.toolTip = "Googly Eyes: Dozing Off 😴"
        }
    }
    
    @MainActor
    private func scheduleNextRandomBlink() {
        randomBlinkTimer?.invalidate()
        let interval = currentEmotion == .stressed ? Double.random(in: 4.5...7.5) : Double.random(in: 2.8...5.5)
        randomBlinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.eyeView?.blink()
                self?.scheduleNextRandomBlink()
            }
        }
    }
    
    @objc private func statusItemClicked() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.currentEmotion == .stressed {
                // Clicking when stressed gives relief and resets work fatigue!
                self.continuousWorkSeconds = 0
                self.triggerHappy(duration: 3.0)
            } else {
                self.eyeView?.doubleBlink()
                self.triggerHappy(duration: 2.0)
            }
        }
    }
}

// MARK: - Googly Eyes Custom NSView with Full Emotion Engine

final class GooglyEyesView: NSView {
    private(set) var isBlinking: Bool = false
    private var blinkTimer: Timer?
    private var emotion: EyeEmotion = .normal
    private var dizzyAngle: CGFloat = 0
    private var eyeScale: CGFloat = 1.0
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setEyeScale(_ scale: CGFloat) {
        self.eyeScale = max(0.4, min(2.0, scale))
        needsDisplay = true
    }
    
    func setEmotion(_ newEmotion: EyeEmotion) {
        self.emotion = newEmotion
        needsDisplay = true
    }
    
    func updateDizzyAngle(_ angle: CGFloat) {
        self.dizzyAngle = angle
    }
    
    func blink() {
        guard emotion != .sleepy else { return }
        blinkTimer?.invalidate()
        isBlinking = true
        needsDisplay = true
        
        let duration = emotion == .stressed ? 0.22 : 0.14
        blinkTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isBlinking = false
                self?.needsDisplay = true
            }
        }
    }
    
    func doubleBlink() {
        blink()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.blink()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        
        let midY = bounds.midY
        let baseRadius: CGFloat = 10.0
        let eyeRadius: CGFloat = baseRadius * eyeScale
        let spacing: CGFloat = eyeRadius * 0.45
        let centerX = bounds.midX
        let leftEyeCenter = CGPoint(x: centerX - eyeRadius - spacing / 2.0, y: midY)
        let rightEyeCenter = CGPoint(x: centerX + eyeRadius + spacing / 2.0, y: midY)
        
        if isBlinking {
            // Closed eyelid blink
            drawClosedEye(center: leftEyeCenter, radius: eyeRadius)
            drawClosedEye(center: rightEyeCenter, radius: eyeRadius)
        } else {
            switch emotion {
            case .normal:
                let mousePos = NSEvent.mouseLocation
                drawOpenEye(center: leftEyeCenter, radius: eyeRadius, mousePos: mousePos, isStressed: false)
                drawOpenEye(center: rightEyeCenter, radius: eyeRadius, mousePos: mousePos, isStressed: false)
                
            case .happy:
                drawHappyEye(center: leftEyeCenter, radius: eyeRadius)
                drawHappyEye(center: rightEyeCenter, radius: eyeRadius)
                
            case .sleepy:
                drawSleepyEye(center: leftEyeCenter, radius: eyeRadius)
                drawSleepyEye(center: rightEyeCenter, radius: eyeRadius)
                
            case .stressed:
                let mousePos = NSEvent.mouseLocation
                drawOpenEye(center: leftEyeCenter, radius: eyeRadius, mousePos: mousePos, isStressed: true)
                drawOpenEye(center: rightEyeCenter, radius: eyeRadius, mousePos: mousePos, isStressed: true)
                drawSweatDrop(center: CGPoint(x: rightEyeCenter.x + eyeRadius + 4.5 * eyeScale, y: midY + 4.0 * eyeScale), scale: eyeScale)
                
            case .dizzy:
                drawDizzyEye(center: leftEyeCenter, radius: eyeRadius, clockwise: true)
                drawDizzyEye(center: rightEyeCenter, radius: eyeRadius, clockwise: false)
            }
        }
        
        context.restoreGState()
    }
    
    // MARK: - Open / Stressed Eye
    
    private func drawOpenEye(center: CGPoint, radius: CGFloat, mousePos: CGPoint, isStressed: Bool) {
        // 1. Eyeball White
        let eyeRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let eyePath = NSBezierPath(ovalIn: eyeRect)
        NSColor.white.setFill()
        eyePath.fill()
        
        // Subtle outline for depth
        NSColor.black.withAlphaComponent(0.28).setStroke()
        eyePath.lineWidth = max(0.8, 1.1 * eyeScale)
        eyePath.stroke()
        
        // 2. Pupil Calculation
        var pupilCenter = center
        let pupilRadius: CGFloat = (isStressed ? 4.2 : 4.8) * eyeScale
        if let window = self.window {
            let windowPoint = self.convert(center, to: nil)
            let screenPoint = window.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
            
            let dx = mousePos.x - screenPoint.x
            let dy = mousePos.y - screenPoint.y
            let angle = atan2(dy, dx)
            let dist = hypot(dx, dy)
            
            let maxOffset: CGFloat = max(1.0, radius - pupilRadius - 0.8 * eyeScale)
            let offset = min(dist / max(1.0, 28.0 * eyeScale), maxOffset)
            
            pupilCenter = CGPoint(
                x: center.x + cos(angle) * offset,
                y: center.y + sin(angle) * offset
            )
        }
        
        // 3. Black Pupil
        let pupilRect = NSRect(
            x: pupilCenter.x - pupilRadius,
            y: pupilCenter.y - pupilRadius,
            width: pupilRadius * 2,
            height: pupilRadius * 2
        )
        let pupilPath = NSBezierPath(ovalIn: pupilRect)
        NSColor.black.setFill()
        pupilPath.fill()
        
        // 4. White Glint Highlight
        let glintRadius: CGFloat = max(0.8, 1.4 * eyeScale)
        let glintOffset: CGFloat = 1.3 * eyeScale
        let glintRect = NSRect(
            x: pupilCenter.x + glintOffset - glintRadius,
            y: pupilCenter.y + glintOffset - glintRadius,
            width: glintRadius * 2,
            height: glintRadius * 2
        )
        let glintPath = NSBezierPath(ovalIn: glintRect)
        NSColor.white.withAlphaComponent(0.95).setFill()
        glintPath.fill()
        
        // 5. Stressed Heavy Eyelid Overlay
        if isStressed {
            NSGraphicsContext.saveGraphicsState()
            eyePath.addClip()
            
            // Drooping heavy top eyelid covering upper 40% of the eye
            let droopPath = NSBezierPath()
            let isLeft = center.x < bounds.midX
            let topY = center.y + radius + 1
            let startY = isLeft ? center.y + 0.5 * eyeScale : center.y + 2.5 * eyeScale
            let endY = isLeft ? center.y + 2.5 * eyeScale : center.y + 0.5 * eyeScale
            
            droopPath.move(to: CGPoint(x: center.x - radius - 1, y: topY))
            droopPath.line(to: CGPoint(x: center.x + radius + 1, y: topY))
            droopPath.line(to: CGPoint(x: center.x + radius + 1, y: endY))
            droopPath.curve(
                to: CGPoint(x: center.x - radius - 1, y: startY),
                controlPoint1: CGPoint(x: center.x + (isLeft ? -1.0 : 1.0) * eyeScale, y: center.y + 1.0 * eyeScale),
                controlPoint2: CGPoint(x: center.x + (isLeft ? 2.0 : -2.0) * eyeScale, y: center.y + 1.5 * eyeScale)
            )
            droopPath.close()
            
            NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 0.95).setFill()
            droopPath.fill()
            
            // Eyelid crease line
            NSColor.white.withAlphaComponent(0.8).setStroke()
            droopPath.lineWidth = max(0.8, 1.2 * eyeScale)
            droopPath.stroke()
            
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    
    // MARK: - Happy / Excited Eye (Smiling anime curves)
    
    private func drawHappyEye(center: CGPoint, radius: CGFloat) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - radius + 1.5 * eyeScale, y: center.y - 1.5 * eyeScale))
        path.curve(
            to: CGPoint(x: center.x + radius - 1.5 * eyeScale, y: center.y - 1.5 * eyeScale),
            controlPoint1: CGPoint(x: center.x - 3.5 * eyeScale, y: center.y + 6.0 * eyeScale),
            controlPoint2: CGPoint(x: center.x + 3.5 * eyeScale, y: center.y + 6.0 * eyeScale)
        )
        
        NSColor.white.withAlphaComponent(0.95).setStroke()
        path.lineWidth = max(1.4, 2.6 * eyeScale)
        path.lineCapStyle = .round
        path.stroke()
    }
    
    // MARK: - Sleepy / Dozing Eye
    
    private func drawSleepyEye(center: CGPoint, radius: CGFloat) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - radius + 1.5 * eyeScale, y: center.y + 0.5 * eyeScale))
        path.curve(
            to: CGPoint(x: center.x + radius - 1.5 * eyeScale, y: center.y + 0.5 * eyeScale),
            controlPoint1: CGPoint(x: center.x - 3.0 * eyeScale, y: center.y - 2.5 * eyeScale),
            controlPoint2: CGPoint(x: center.x + 3.0 * eyeScale, y: center.y - 2.5 * eyeScale)
        )
        
        NSColor.white.withAlphaComponent(0.85).setStroke()
        path.lineWidth = max(1.2, 2.2 * eyeScale)
        path.lineCapStyle = .round
        path.stroke()
    }
    
    // MARK: - Dizzy Eye (Spinning spiral pupils)
    
    private func drawDizzyEye(center: CGPoint, radius: CGFloat, clockwise: Bool) {
        // Eyeball White
        let eyeRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let eyePath = NSBezierPath(ovalIn: eyeRect)
        NSColor.white.setFill()
        eyePath.fill()
        
        NSColor.black.withAlphaComponent(0.28).setStroke()
        eyePath.lineWidth = max(0.8, 1.1 * eyeScale)
        eyePath.stroke()
        
        // Orbiting Pupil
        let angle = clockwise ? dizzyAngle : -dizzyAngle
        let orbitRadius: CGFloat = max(1.0, radius - 5.0 * eyeScale)
        let pupilCenter = CGPoint(
            x: center.x + cos(angle) * orbitRadius,
            y: center.y + sin(angle) * orbitRadius
        )
        
        let pupilRadius: CGFloat = max(1.5, 3.8 * eyeScale)
        let pupilRect = NSRect(x: pupilCenter.x - pupilRadius, y: pupilCenter.y - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: pupilRect).fill()
        
        // Inner spiral tick
        let spiral = NSBezierPath()
        spiral.move(to: center)
        spiral.line(to: pupilCenter)
        NSColor.black.withAlphaComponent(0.45).setStroke()
        spiral.lineWidth = max(0.8, 1.2 * eyeScale)
        spiral.stroke()
    }
    
    // MARK: - Normal Closed Blink
    
    private func drawClosedEye(center: CGPoint, radius: CGFloat) {
        let path = NSBezierPath()
        let startPoint = CGPoint(x: center.x - radius + 1.0 * eyeScale, y: center.y - 1.0 * eyeScale)
        let endPoint = CGPoint(x: center.x + radius - 1.0 * eyeScale, y: center.y - 1.0 * eyeScale)
        let controlPoint = CGPoint(x: center.x, y: center.y + 4.8 * eyeScale)
        
        path.move(to: startPoint)
        path.curve(to: endPoint, controlPoint1: controlPoint, controlPoint2: controlPoint)
        
        NSColor.white.withAlphaComponent(0.95).setStroke()
        path.lineWidth = max(1.2, 2.4 * eyeScale)
        path.lineCapStyle = .round
        path.stroke()
    }
    
    // MARK: - Sweat Droplet (Anime stress tear)
    
    private func drawSweatDrop(center: CGPoint, scale: CGFloat) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y + 4.5 * scale))
        path.curve(
            to: CGPoint(x: center.x + 2.8 * scale, y: center.y - 1.5 * scale),
            controlPoint1: CGPoint(x: center.x + 1.0 * scale, y: center.y + 2.0 * scale),
            controlPoint2: CGPoint(x: center.x + 2.8 * scale, y: center.y)
        )
        path.appendArc(
            withCenter: CGPoint(x: center.x, y: center.y - 1.5 * scale),
            radius: max(1.0, 2.8 * scale),
            startAngle: 0,
            endAngle: 180
        )
        path.curve(
            to: CGPoint(x: center.x, y: center.y + 4.5 * scale),
            controlPoint1: CGPoint(x: center.x - 2.8 * scale, y: center.y),
            controlPoint2: CGPoint(x: center.x - 1.0 * scale, y: center.y + 2.0 * scale)
        )
        path.close()
        
        // Bright vibrant cyan drop
        NSColor(red: 0.28, green: 0.76, blue: 0.98, alpha: 0.95).setFill()
        path.fill()
        
        // Highlight glint
        let glint = NSBezierPath(ovalIn: NSRect(x: center.x + 0.6 * scale, y: center.y - 1.8 * scale, width: max(0.6, 1.2 * scale), height: max(0.8, 1.8 * scale)))
        NSColor.white.withAlphaComponent(0.85).setFill()
        glint.fill()
    }
}
