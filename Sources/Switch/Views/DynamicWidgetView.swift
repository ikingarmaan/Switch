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
    
    public init() {}
}

public struct DynamicWidgetView: View {
    public let widget: CustomWidget
    public let onClose: () -> Void
    public let onTogglePin: () -> Void
    
    @StateObject private var state = DynamicWidgetViewState()
    
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
        VStack(spacing: 0) {
            // Header Bar (Window controls + Native Drag Area)
            ZStack {
                // Background native drag area spanning the header
                WidgetDragAreaView()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: accentColor.opacity(0.8), radius: 3)
                        .allowsHitTesting(false)
                    
                    Text(widget.name.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(0.6)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                    
                    // Subtle drag handle grip
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .allowsHitTesting(false)
                    
                    Spacer()
                        .allowsHitTesting(false)
                    
                    // Pin button
                    Button(action: onTogglePin) {
                        Image(systemName: widget.isPinnedToDesktop ? "pin.fill" : "pin.slash")
                            .font(.system(size: 10))
                            .foregroundColor(widget.isPinnedToDesktop ? accentColor : .white.opacity(0.6))
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(widget.isPinnedToDesktop ? "Pinned to Desktop (Click to float)" : "Floating Window (Click to pin)")
                    
                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Close Widget")
                }
            }
            .frame(height: 26)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            // Content Body
            Group {
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
            .allowsHitTesting(isContentInteractive)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: widget.width, height: widget.height)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                backgroundGradient
                WidgetDragAreaView()
            }
        )
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
        .contextMenu {
            Button(action: onTogglePin) {
                Label(
                    widget.isPinnedToDesktop ? "Float on Top" : "Pin to Desktop",
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
    }
    
    private var isContentInteractive: Bool {
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
        HStack(spacing: 16) {
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
            .frame(width: 80, height: 80)
            
            // Digital Box
            VStack(alignment: .leading, spacing: 3) {
                Text(greetingText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(formattedTime(state.currentTime))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formattedDate(state.currentTime))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
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
    
    // MARK: - 11. Custom Content
    
    private var customContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widget.prompt)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(2)
            
            HStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("Active")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentColor)
                    Text("STATUS")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
                
                VStack(spacing: 2) {
                    Text("100%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("READY")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
            }
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
