import SwiftUI
import AppKit

// MARK: - Native Widget Drag Area
public struct WidgetDragAreaView: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> WidgetDragNSView {
        WidgetDragNSView()
    }
    
    public func updateNSView(_ nsView: WidgetDragNSView, context: Context) {}
    
    public final class WidgetDragNSView: NSView {
        public override var mouseDownCanMoveWindow: Bool { true }
        
        public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            return true
        }
        
        public override func mouseDown(with event: NSEvent) {
            guard let window = self.window else { return }
            window.performDrag(with: event)
        }
    }
}

// MARK: - Todo Item Model
public struct WidgetTodoItem: Identifiable {
    public let id: UUID
    public var text: String
    public var isDone: Bool
    
    public init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

// MARK: - View State (No @State macro to avoid SwiftUIMacros compiler issues)
public final class DynamicWidgetViewState: ObservableObject {
    @Published public var currentTime: Date = Date()
    @Published public var pomoSeconds: Int = 25 * 60
    @Published public var isPomoRunning: Bool = false
    @Published public var isPomoBreak: Bool = false
    @Published public var newTaskText: String = ""
    @Published public var todoItems: [WidgetTodoItem] = [
        WidgetTodoItem(text: "Review project pull request", isDone: false),
        WidgetTodoItem(text: "Design new widget layout", isDone: false),
        WidgetTodoItem(text: "Coffee & daily planning", isDone: true)
    ]
    @Published public var calcDisplay: String = "0"
    @Published public var calcPendingOp: String? = nil
    @Published public var calcPreviousVal: Double = 0
    @Published public var calcNeedsReset: Bool = false
    @Published public var habitDays: [Bool] = [true, true, true, true, true, true, false]
    @Published public var quoteIndex: Int = 0
    @Published public var cpuVal: Int = 24
    @Published public var ramVal: Int = 58
    @Published public var isHovered: Bool = false
    
    // Dynamic AI Component State
    @Published public var dynamicProgress: Double = 0
    @Published public var dynamicCurrencyInput: String = "100"
    @Published public var dynamicNoteText: String = ""
    @Published public var dynamicToggles: [String: Bool] = [:]
    @Published public var copiedToast: Bool = false
    @Published public var isInitialized: Bool = false
    
    public init() {}
}

public struct DynamicWidgetView: View {
    public let widget: CustomWidget
    public let onClose: () -> Void
    public let onTogglePin: () -> Void
    
    @StateObject private var state = DynamicWidgetViewState()
    @ObservedObject private var sysMonitor = SystemMonitorService.shared
    
    private let quotes = [
        ("Simplicity is the ultimate sophistication.", "Leonardo da Vinci"),
        ("Make it simple, but significant.", "Don Draper"),
        ("Stay hungry, stay foolish.", "Steve Jobs"),
        ("Focus is a muscle that strengthens with practice.", "Anonymous")
    ]
    
    public init(widget: CustomWidget, onClose: @escaping () -> Void, onTogglePin: @escaping () -> Void) {
        self.widget = widget
        self.onClose = onClose
        self.onTogglePin = onTogglePin
    }
    
    public var body: some View {
        ZStack {
            // 1. Native Window Drag Area filling the entire card surface
            WidgetDragAreaView()
            
            // 2. Pure Widget Content (Spacious, beautifully centered)
            Group {
                if let comps = resolvedComponents, !comps.isEmpty {
                    dynamicComponentsView(comps: comps)
                } else {
                    switch widget.category {
                    case "clock":
                        clockContent
                    case "crypto":
                        cryptoContent
                    case "pomodoro":
                        pomodoroContent
                    case "gauges":
                        gaugesContent
                    case "todo":
                        todoContent
                    case "weather":
                        weatherContent
                    case "habit":
                        habitContent
                    case "calc":
                        calculatorContent
                    case "countdown":
                        countdownContent
                    case "quote":
                        quoteContent
                    default:
                        customContent
                    }
                }
            }
            .allowsHitTesting(isContentInteractive)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 3. Subtle Floating Window Controls (Smooth on hover, native macOS widget style)
            VStack {
                HStack(spacing: 6) {
                    // Title badge on hover
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: accentColor.opacity(0.8), radius: 3)
                        Text(widget.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .allowsHitTesting(false)
                    
                    Spacer()
                    
                    // Pin / Float button
                    Button(action: onTogglePin) {
                        Image(systemName: widget.isPinnedToDesktop ? "pin.fill" : "pin.slash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(widget.isPinnedToDesktop ? accentColor : .white.opacity(0.85))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .help(widget.isPinnedToDesktop ? "Pinned to Wallpaper (Click to float)" : "Floating Window (Click to pin)")
                    
                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .help("Close Widget")
                }
                .opacity(state.isHovered ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.16), value: state.isHovered)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                Spacer()
            }
        }
        .frame(width: widget.width, height: widget.height)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                backgroundGradient
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        .onHover { hovering in
            state.isHovered = hovering
        }
        .contextMenu {
            Button(action: onTogglePin) {
                Label(
                    widget.isPinnedToDesktop ? "Float on Top" : "Pin to Wallpaper",
                    systemImage: widget.isPinnedToDesktop ? "arrow.up.and.line.horizontal.and.arrow.down" : "pin.fill"
                )
            }
            Button(action: {
                WidgetStudioService.shared.openStudio()
            }) {
                Label("Open Widget Studio...", systemImage: "sparkles")
            }
            Divider()
            Button(role: .destructive, action: onClose) {
                Label("Close Widget", systemImage: "xmark")
            }
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { now in
            self.state.currentTime = now
            if self.state.isPomoRunning && self.state.pomoSeconds > 0 {
                self.state.pomoSeconds -= 1
            }
        }
        .onAppear {
            initDynamicComponentsIfNeeded()
        }
    }
    
    private var resolvedComponents: [WidgetComponent]? {
        if let comps = widget.components, !comps.isEmpty {
            return comps
        }
        if widget.category == "ai_generated" || widget.category == "custom" {
            return WidgetGenerator.shared.generate(from: widget.prompt, theme: widget.theme).components
        }
        return nil
    }
    
    private func initDynamicComponentsIfNeeded() {
        guard !state.isInitialized else { return }
        state.isInitialized = true
        if let comps = resolvedComponents {
            for comp in comps {
                if comp.type == .progressBar, let val = comp.progressValue {
                    state.dynamicProgress = val
                }
                if comp.type == .textNote, let note = comp.noteText {
                    state.dynamicNoteText = note
                }
                if comp.type == .toggleList, let toggles = comp.toggles {
                    for t in toggles {
                        state.dynamicToggles[t.id] = t.isOn
                    }
                }
            }
        }
        SystemMonitorService.shared.sampleMetrics()
    }
    
    private var isContentInteractive: Bool {
        if widget.category == "ai_generated" || (resolvedComponents != nil && !resolvedComponents!.isEmpty) {
            return true
        }
        switch widget.category {
        case "pomodoro", "todo", "habit", "calc", "quote":
            return true
        default:
            return false
        }
    }
    
    // MARK: - Themes
    
    private var accentColor: Color {
        switch widget.theme {
        case "neon": return Color(red: 0.0, green: 0.95, blue: 1.0)
        case "sunset": return Color(red: 1.0, green: 0.45, blue: 0.35)
        case "minimal": return Color.white
        default: return Color(red: 0.28, green: 0.76, blue: 0.52)
        }
    }
    
    private var backgroundGradient: some View {
        Group {
            switch widget.theme {
            case "neon":
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.08, blue: 0.16).opacity(0.85), Color(red: 0.12, green: 0.04, blue: 0.14).opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "sunset":
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.08, blue: 0.12).opacity(0.88), Color(red: 0.12, green: 0.07, blue: 0.15).opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "minimal":
                Color(red: 0.10, green: 0.10, blue: 0.11).opacity(0.92)
            default:
                Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.85)
            }
        }
    }
    
    // MARK: - 1. Clock View
    
    private var clockContent: some View {
        HStack(spacing: 18) {
            // Analog Clock
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)
                    .background(Circle().fill(Color.black.opacity(0.2)))
                
                // Clock Hands
                ClockHandsView(date: state.currentTime, accent: accentColor)
                
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 86, height: 86)
            
            // Digital Box
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(formattedTime(state.currentTime))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formattedDate(state.currentTime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(5)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: state.currentTime)
        if hour < 12 { return "Good Morning" }
        if hour < 17 { return "Good Afternoon" }
        return "Good Evening"
    }
    
    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
    
    // MARK: - 2. Crypto View
    
    private var cryptoContent: some View {
        VStack(spacing: 6) {
            cryptoRow(symbol: "₿", name: "Bitcoin", price: "$68,450", change: "+3.4%", isUp: true, color: Color(red: 0.97, green: 0.58, blue: 0.10))
            cryptoRow(symbol: "Ξ", name: "Ethereum", price: "$3,620", change: "+2.1%", isUp: true, color: Color(red: 0.38, green: 0.49, blue: 0.92))
            cryptoRow(symbol: "◎", name: "Solana", price: "$178.20", change: "-1.2%", isUp: false, color: Color(red: 0.08, green: 0.95, blue: 0.58))
        }
        .frame(maxHeight: .infinity)
    }
    
    private func cryptoRow(symbol: String, name: String, price: String, change: String, isUp: Bool, color: Color) -> some View {
        HStack {
            ZStack {
                Circle().fill(color).frame(width: 22, height: 22)
                Text(symbol).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(price).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white)
                Text(change).font(.system(size: 9.5, weight: .bold)).foregroundColor(isUp ? Color(red: 0.28, green: 0.76, blue: 0.52) : Color.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
    
    // MARK: - 3. Pomodoro View
    
    private var pomodoroContent: some View {
        VStack(spacing: 8) {
            Text(state.isPomoBreak ? "☕ Coffee Break" : "🔥 Focus Session")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accentColor)
            
            Text(String(format: "%02d:%02d", state.pomoSeconds / 60, state.pomoSeconds % 60))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 8) {
                Button(action: { state.isPomoRunning.toggle() }) {
                    Text(state.isPomoRunning ? "Pause" : "Start")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.05, green: 0.08, blue: 0.12))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    state.isPomoRunning = false
                    state.pomoSeconds = state.isPomoBreak ? 5 * 60 : 25 * 60
                }) {
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    state.isPomoBreak.toggle()
                    state.isPomoRunning = false
                    state.pomoSeconds = state.isPomoBreak ? 5 * 60 : 25 * 60
                }) {
                    Text(state.isPomoBreak ? "Focus Mode" : "Break")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - 4. Gauges View
    
    private var gaugesContent: some View {
        HStack(spacing: 12) {
            gaugeRing(label: "⚡ CPU", value: state.cpuVal, color: accentColor)
            gaugeRing(label: "🧠 RAM", value: state.ramVal, color: Color(red: 0.35, green: 0.65, blue: 1.0))
            gaugeRing(label: "🔋 Bat", value: 85, color: Color(red: 0.28, green: 0.76, blue: 0.52))
        }
        .frame(maxHeight: .infinity)
    }
    
    private func gaugeRing(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(value) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)%")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 54, height: 54)
            
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
    
    // MARK: - 5. Todo View
    
    private var todoContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Add task...", text: $state.newTaskText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .onSubmit(addTask)
                
                Button(action: addTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.05, green: 0.08, blue: 0.12))
                        .padding(5)
                        .background(accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(state.todoItems) { item in
                        HStack {
                            Button(action: {
                                if let idx = state.todoItems.firstIndex(where: { $0.id == item.id }) {
                                    state.todoItems[idx].isDone.toggle()
                                }
                            }) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(item.isDone ? accentColor : .gray)
                            }
                            .buttonStyle(.plain)
                            
                            Text(item.text)
                                .font(.system(size: 11))
                                .strikethrough(item.isDone)
                                .foregroundColor(item.isDone ? .gray : .white)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button(action: {
                                state.todoItems.removeAll { $0.id == item.id }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func addTask() {
        let t = state.newTaskText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        state.todoItems.insert(WidgetTodoItem(text: t, isDone: false), at: 0)
        state.newTaskText = ""
    }
    
    // MARK: - 6. Weather View
    
    private var weatherContent: some View {
        HStack(spacing: 14) {
            Text("🌤")
                .font(.system(size: 44))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("22°C")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Partly Cloudy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                Text("💧 48% Hum")
                Text("💨 14 km/h")
                Text("📍 Local")
            }
            .font(.system(size: 10.5))
            .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - 7. Habit View
    
    private var habitContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text("💧 Daily Goal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("🔥 6 Day Streak")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accentColor)
            }
            
            HStack(spacing: 6) {
                let days = ["M", "T", "W", "T", "F", "S", "S"]
                ForEach(0..<7) { idx in
                    Button(action: { state.habitDays[idx].toggle() }) {
                        VStack(spacing: 3) {
                            Text(days[idx])
                                .font(.system(size: 9, weight: .bold))
                            Image(systemName: state.habitDays[idx] ? "checkmark" : "circle")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundColor(state.habitDays[idx] ? Color(red: 0.05, green: 0.08, blue: 0.12) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(state.habitDays[idx] ? accentColor : Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - 8. Calculator View
    
    private var calculatorContent: some View {
        VStack(spacing: 4) {
            Text(state.calcDisplay)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(6)
                .background(Color.black.opacity(0.25))
                .cornerRadius(6)
            
            let grid: [[String]] = [
                ["C", "±", "%", "÷"],
                ["7", "8", "9", "×"],
                ["4", "5", "6", "−"],
                ["1", "2", "3", "+"],
                ["0", ".", "="]
            ]
            
            ForEach(grid, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Button(action: { handleCalcKey(key) }) {
                            Text(key)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(key == "=" ? Color(red: 0.05, green: 0.08, blue: 0.12) : .white)
                                .frame(maxWidth: key == "0" ? .infinity : 40, maxHeight: 22)
                                .background(key == "=" ? accentColor : Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func handleCalcKey(_ key: String) {
        if key == "C" {
            state.calcDisplay = "0"
            state.calcPendingOp = nil
            state.calcPreviousVal = 0
            state.calcNeedsReset = false
        } else if let num = Int(key) {
            if state.calcDisplay == "0" || state.calcNeedsReset {
                state.calcDisplay = "\(num)"
                state.calcNeedsReset = false
            } else {
                state.calcDisplay += "\(num)"
            }
        } else if key == "." {
            if !state.calcDisplay.contains(".") { state.calcDisplay += "." }
        } else if key == "=" {
            if let op = state.calcPendingOp, let cur = Double(state.calcDisplay) {
                var res: Double = 0
                switch op {
                case "+": res = state.calcPreviousVal + cur
                case "−": res = state.calcPreviousVal - cur
                case "×": res = state.calcPreviousVal * cur
                case "÷": res = cur != 0 ? state.calcPreviousVal / cur : 0
                default: break
                }
                state.calcDisplay = res.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(res))" : String(format: "%.2f", res)
                state.calcPendingOp = nil
                state.calcNeedsReset = true
            }
        } else {
            state.calcPreviousVal = Double(state.calcDisplay) ?? 0
            state.calcPendingOp = key
            state.calcNeedsReset = true
        }
    }
    
    // MARK: - 9. Countdown View
    
    private var countdownContent: some View {
        VStack(spacing: 8) {
            Text("🎯 Target Milestone")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            
            HStack(spacing: 8) {
                countdownBox(number: "76", label: "Days")
                countdownBox(number: "14", label: "Hours")
                countdownBox(number: "32", label: "Mins")
                countdownBox(number: "45", label: "Secs")
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func countdownBox(number: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(number)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
    }
    
    // MARK: - 10. Quote View
    
    private var quoteContent: some View {
        Button(action: {
            state.quoteIndex = (state.quoteIndex + 1) % quotes.count
        }) {
            VStack(spacing: 6) {
                Text("“\(quotes[state.quoteIndex].0)”")
                    .font(.system(size: 12.5, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                
                Text("— \(quotes[state.quoteIndex].1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accentColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 11. Dynamic AI Generated Components Engine
    
    private func dynamicComponentsView(comps: [WidgetComponent]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(comps.enumerated()), id: \.offset) { _, comp in
                switch comp.type {
                case .header:
                    dynamicHeaderView(comp)
                case .metricsGrid:
                    dynamicMetricsView(comp)
                case .progressBar:
                    dynamicProgressBarView(comp)
                case .actionButtons:
                    dynamicActionButtonsView(comp)
                case .toggleList:
                    dynamicToggleListView(comp)
                case .liveSystemStat:
                    dynamicSystemStatView(comp)
                case .currencyCalc:
                    dynamicCurrencyCalcView(comp)
                case .worldClocks:
                    dynamicWorldClocksView(comp)
                case .quickApps:
                    dynamicQuickAppsView(comp)
                case .textNote:
                    dynamicTextNoteView(comp)
                case .quote:
                    dynamicQuoteView(comp)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Component Subviews
    
    private func dynamicHeaderView(_ comp: WidgetComponent) -> some View {
        HStack(spacing: 8) {
            if let icon = comp.icon, !icon.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(comp.title ?? widget.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = comp.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
    }
    
    private func dynamicMetricsView(_ comp: WidgetComponent) -> some View {
        guard let metrics = comp.metrics, !metrics.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            HStack(spacing: 6) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            if let icon = metric.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(colorFromHex(metric.colorHex) ?? accentColor)
                            }
                            Text(metric.label)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.55))
                                .tracking(0.5)
                        }
                        
                        Text(metric.value)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(colorFromHex(metric.colorHex) ?? .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        
                        if let sub = metric.subtext {
                            Text(sub)
                                .font(.system(size: 7.5))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
            }
        )
    }
    
    private func dynamicProgressBarView(_ comp: WidgetComponent) -> some View {
        let maxVal = comp.progressMax ?? 100
        let currentVal = state.dynamicProgress
        let pct = maxVal > 0 ? min(max(currentVal / maxVal, 0.0), 1.0) : 0.0
        let color = colorFromHex(comp.progressColorHex) ?? accentColor
        
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(comp.title ?? "Goal Progress")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(currentVal)) / \(Int(maxVal)) \(comp.progressUnit ?? "")")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 7)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * CGFloat(pct), 4), height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pct)
                }
            }
            .frame(height: 7)
        }
    }
    
    private func dynamicActionButtonsView(_ comp: WidgetComponent) -> some View {
        guard let buttons = comp.buttons, !buttons.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            HStack(spacing: 6) {
                ForEach(buttons, id: \.id) { btn in
                    Button(action: {
                        handleActionButton(btn: btn)
                    }) {
                        HStack(spacing: 4) {
                            if let icon = btn.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            Text(btn.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        )
    }
    
    private func dynamicSystemStatView(_ comp: WidgetComponent) -> some View {
        let type = comp.systemStatType ?? "battery"
        
        return HStack(spacing: 8) {
            switch type {
            case "battery":
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(sysMonitor.isCharging ? Color.green.opacity(0.2) : accentColor.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: sysMonitor.isCharging ? "bolt.batteryblock.fill" : "battery.100")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(sysMonitor.isCharging ? .green : accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(sysMonitor.batteryPercent)%")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            if sysMonitor.isCharging {
                                Text("CHARGING")
                                    .font(.system(size: 7.5, weight: .heavy))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.green.opacity(0.2)))
                            }
                        }
                        Text("\(sysMonitor.batteryCondition) • \(sysMonitor.batteryCycleCount) Cycles • \(sysMonitor.batteryHealthPercent)% Health")
                            .font(.system(size: 8.5))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                
            case "cpu":
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(sysMonitor.cpuPercent))%")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(accentColor)
                        Text("CPU LOAD")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Divider().frame(height: 22).background(Color.white.opacity(0.15))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sysMonitor.chipName.isEmpty ? "Apple Silicon" : sysMonitor.chipName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("\(sysMonitor.coreCount) Cores • \(sysMonitor.threadCount) Threads")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                }
                
            case "ram":
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(sysMonitor.ramPercent))%")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(sysMonitor.memoryPressureState.color)
                        Text("MEMORY")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Divider().frame(height: 22).background(Color.white.opacity(0.15))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: "%.1f", Double(sysMonitor.ramUsedBytes) / 1_073_741_824.0)) GB used")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Total \(sysMonitor.totalRAMFormatted) • \(sysMonitor.memoryPressureState.rawValue)")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                }
                
            case "storage":
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: "%.1f", Double(sysMonitor.ssdFreeBytes) / 1_073_741_824.0)) GB Free")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.white)
                        Text("Macintosh HD • \(sysMonitor.totalSSDFormatted) Total")
                            .font(.system(size: 8.5))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }
    
    private func dynamicCurrencyCalcView(_ comp: WidgetComponent) -> some View {
        let from = comp.currencyFrom ?? "USD"
        let to = comp.currencyTo ?? "INR"
        let rate = comp.currencyRate ?? 84.15
        let amount = Double(state.dynamicCurrencyInput) ?? 100
        let converted = amount * rate
        
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(from)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                    TextField("100", text: $state.dynamicCurrencyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 55)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(accentColor)
                
                HStack(spacing: 4) {
                    Text(to)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(format: "%.2f", converted))
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundColor(accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                
                Spacer()
            }
        }
    }
    
    private func dynamicWorldClocksView(_ comp: WidgetComponent) -> some View {
        let cities = comp.clockCities ?? ["Cupertino", "London", "Tokyo", "New Delhi"]
        
        return HStack(spacing: 6) {
            ForEach(cities, id: \.self) { city in
                let info = timeForCity(city)
                VStack(spacing: 2) {
                    Text(city)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                    Text(info.time)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(info.offset)
                        .font(.system(size: 7))
                        .foregroundColor(accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }
    
    private func dynamicQuickAppsView(_ comp: WidgetComponent) -> some View {
        let apps = comp.appNames ?? ["Safari", "Terminal", "Notes", "Code"]
        
        return HStack(spacing: 6) {
            ForEach(apps, id: \.self) { app in
                Button(action: {
                    launchApplication(name: app)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: sfSymbolForApp(app))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accentColor)
                        Text(app)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func dynamicTextNoteView(_ comp: WidgetComponent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                TextField("Jot quick note...", text: $state.dynamicNoteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3...4)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                
                if state.copiedToast {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                        Text("Copied")
                    }
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(4)
                }
            }
        }
    }
    
    private func dynamicToggleListView(_ comp: WidgetComponent) -> some View {
        guard let toggles = comp.toggles, !toggles.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(spacing: 4) {
                ForEach(toggles, id: \.id) { item in
                    let isOn = state.dynamicToggles[item.id] ?? item.isOn
                    Button(action: {
                        state.dynamicToggles[item.id] = !isOn
                    }) {
                        HStack {
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(isOn ? accentColor : .white.opacity(0.5))
                            }
                            Text(item.label)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundColor(isOn ? accentColor : .white.opacity(0.3))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        )
    }
    
    private func dynamicQuoteView(_ comp: WidgetComponent) -> some View {
        VStack(spacing: 4) {
            Text("\"\(comp.title ?? "Simplicity is the ultimate sophistication.")\"")
                .font(.system(size: 10.5, weight: .medium, design: .serif))
                .italic()
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            if let author = comp.subtitle {
                Text("— \(author)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
    }
    
    // MARK: - Action Handlers & Native macOS Integrations
    
    private func handleActionButton(btn: WidgetActionButton) {
        switch btn.actionType {
        case "increment":
            let delta = Double(btn.payload ?? "250") ?? 250
            state.dynamicProgress += delta
        case "decrement":
            let delta = Double(btn.payload ?? "250") ?? 250
            state.dynamicProgress = max(0, state.dynamicProgress - delta)
        case "reset":
            state.dynamicProgress = 0
        case "launchApp":
            let app = btn.payload ?? btn.label
            launchApplication(name: app)
        case "togglePlay", "nextTrack", "prevTrack":
            executeMusicCommand(btn.actionType)
        case "emptyTrash":
            emptyTrash()
        case "lowPowerToggle":
            if let prefURL = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                NSWorkspace.shared.open(prefURL)
            }
        case "openSettings":
            if let payload = btn.payload, let url = URL(string: payload) {
                NSWorkspace.shared.open(url)
            }
        case "copyNote":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.dynamicNoteText, forType: .string)
            state.copiedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                state.copiedToast = false
            }
        case "clearNote":
            state.dynamicNoteText = ""
        case "openStudio":
            WidgetStudioService.shared.openStudio()
        case "refresh":
            SystemMonitorService.shared.sampleMetrics()
        default:
            if let payload = btn.payload, let url = URL(string: payload) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func launchApplication(name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        try? process.run()
    }
    
    private func executeMusicCommand(_ cmd: String) {
        let script: String
        switch cmd {
        case "nextTrack":
            script = "tell application \"Music\" to next track"
        case "prevTrack":
            script = "tell application \"Music\" to previous track"
        default:
            script = "tell application \"Music\" to playpause"
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }
    
    private func emptyTrash() {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        }
    }
    
    private func timeForCity(_ city: String) -> (time: String, offset: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        let tz: TimeZone?
        let lower = city.lowercased()
        if lower.contains("cupertino") || lower.contains("san francisco") || lower.contains("la") || lower.contains("pacific") {
            tz = TimeZone(identifier: "America/Los_Angeles")
        } else if lower.contains("new york") || lower.contains("eastern") {
            tz = TimeZone(identifier: "America/New_York")
        } else if lower.contains("london") {
            tz = TimeZone(identifier: "Europe/London")
        } else if lower.contains("tokyo") {
            tz = TimeZone(identifier: "Asia/Tokyo")
        } else if lower.contains("delhi") || lower.contains("mumbai") || lower.contains("india") {
            tz = TimeZone(identifier: "Asia/Kolkata")
        } else if lower.contains("paris") || lower.contains("berlin") {
            tz = TimeZone(identifier: "Europe/Paris")
        } else if lower.contains("sydney") {
            tz = TimeZone(identifier: "Australia/Sydney")
        } else if lower.contains("dubai") {
            tz = TimeZone(identifier: "Asia/Dubai")
        } else if lower.contains("singapore") {
            tz = TimeZone(identifier: "Asia/Singapore")
        } else {
            tz = TimeZone.current
        }
        
        formatter.timeZone = tz ?? TimeZone.current
        let timeStr = formatter.string(from: state.currentTime)
        
        let localSeconds = TimeZone.current.secondsFromGMT(for: state.currentTime)
        let targetSeconds = (tz ?? TimeZone.current).secondsFromGMT(for: state.currentTime)
        let diffHours = Double(targetSeconds - localSeconds) / 3600.0
        let diffStr: String
        if abs(diffHours) < 0.1 {
            diffStr = "Local"
        } else if diffHours > 0 {
            diffStr = String(format: "+%.1f hrs", diffHours).replacingOccurrences(of: ".0", with: "")
        } else {
            diffStr = String(format: "%.1f hrs", diffHours).replacingOccurrences(of: ".0", with: "")
        }
        
        return (timeStr, diffStr)
    }
    
    private func sfSymbolForApp(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("safari") || n.contains("browser") { return "safari" }
        if n.contains("term") || n.contains("iterm") { return "terminal" }
        if n.contains("note") { return "note.text" }
        if n.contains("code") || n.contains("studio") { return "chevron.left.forwardslash.chevron.right" }
        if n.contains("music") || n.contains("spotify") { return "music.note" }
        if n.contains("mail") { return "envelope" }
        if n.contains("calc") { return "plus.slash.minus" }
        if n.contains("cal") { return "calendar" }
        if n.contains("msg") || n.contains("message") { return "message" }
        if n.contains("slack") { return "bubble.left.and.bubble.right" }
        return "app.badge"
    }
    
    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex = hex?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), hex.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    // MARK: - Fallback Custom Content
    
    private var customContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(accentColor)
                Text(widget.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(widget.prompt)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(2)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Analog Clock Hands

private struct ClockHandsView: View {
    let date: Date
    let accent: Color
    
    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let cal = Calendar.current
            let hour = cal.component(.hour, from: date)
            let min = cal.component(.minute, from: date)
            let sec = cal.component(.second, from: date)
            
            let hAngle = Angle.degrees(Double(hour % 12) * 30.0 + Double(min) * 0.5)
            let mAngle = Angle.degrees(Double(min) * 6.0 + Double(sec) * 0.1)
            let sAngle = Angle.degrees(Double(sec) * 6.0)
            
            // Hour hand
            hand(center: center, length: 22, width: 3, angle: hAngle, color: .white)
            // Min hand
            hand(center: center, length: 30, width: 2, angle: mAngle, color: .white.opacity(0.85))
            // Sec hand
            hand(center: center, length: 34, width: 1.5, angle: sAngle, color: accent)
        }
    }
    
    private func hand(center: CGPoint, length: CGFloat, width: CGFloat, angle: Angle, color: Color) -> some View {
        Path { path in
            path.move(to: center)
            let rad = CGFloat(angle.radians - .pi / 2)
            let end = CGPoint(x: center.x + cos(rad) * length, y: center.y + sin(rad) * length)
            path.addLine(to: end)
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
