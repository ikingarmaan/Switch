import Foundation
import Cocoa
import SwiftUI
import Combine

public extension Notification.Name {
    static let habitTrackerStateDidChange = Notification.Name("SwitchHabitTrackerStateDidChange")
    static let habitTrackerDataDidChange = Notification.Name("SwitchHabitTrackerDataDidChange")
}

public final class HabitTrackerPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}

public final class HabitTrackerService: ObservableObject, @unchecked Sendable {
    public static let shared = HabitTrackerService()
    
    @Published public var habits: [Habit] = []
    @Published public var isEnabled: Bool = false
    @Published public var isWindowVisible: Bool = false
    
    private var habitPanel: HabitTrackerPanel?
    private let keyEnabled = "switch.habitTracker.enabled"
    private let keyBackup = "switch.habitTracker.snapshotBackup"
    
    private var saveDebounceTimer: Timer?
    private let queue = DispatchQueue(label: "com.armank.switch.habitTracker", qos: .userInitiated)
    
    private var supportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Switch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var storageFileURL: URL {
        supportDirectory.appendingPathComponent("habits.json")
    }
    
    private var mirrorFileURL: URL {
        supportDirectory.appendingPathComponent("habits_backup.json")
    }
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: keyEnabled)
        loadHabits()
    }
    
    // MARK: - CRUD Actions
    
    @discardableResult
    public func addHabit(name: String, colorHex: String = "#10B981", icon: String = "⚡️") -> Habit {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Habit" : trimmed
        let habit = Habit(name: finalName, colorHex: colorHex, icon: icon)
        habits.append(habit)
        saveHabitsImmediate()
        NotificationCenter.default.post(name: .habitTrackerDataDidChange, object: nil)
        return habit
    }
    
    public func updateHabit(id: UUID, name: String, colorHex: String, icon: String) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        habits[index].colorHex = colorHex
        habits[index].icon = icon
        saveHabitsImmediate()
        NotificationCenter.default.post(name: .habitTrackerDataDidChange, object: nil)
    }
    
    public func deleteHabit(id: UUID) {
        habits.removeAll(where: { $0.id == id })
        saveHabitsImmediate()
        NotificationCenter.default.post(name: .habitTrackerDataDidChange, object: nil)
    }
    
    public func toggleCompletion(habitId: UUID, date: Date) {
        let dateStr = Habit.dateFormatter.string(from: date)
        toggleCompletion(habitId: habitId, dateStr: dateStr)
    }
    
    public func toggleCompletion(habitId: UUID, dateStr: String) {
        guard let index = habits.firstIndex(where: { $0.id == habitId }) else { return }
        habits[index].toggle(dateStr: dateStr)
        saveHabitsImmediate()
        NotificationCenter.default.post(name: .habitTrackerDataDidChange, object: nil)
    }
    
    // MARK: - Progress & Metrics
    
    public var todayCompletionRatio: (completed: Int, total: Int) {
        let todayStr = Habit.dateFormatter.string(from: Date())
        let total = habits.count
        let completed = habits.filter { $0.isCompleted(dateStr: todayStr) }.count
        return (completed, total)
    }
    
    public var statusSubtitle: String {
        guard !habits.isEmpty else { return "0 Habits" }
        let (done, total) = todayCompletionRatio
        let percent = total > 0 ? Int((Double(done) / Double(total)) * 100) : 0
        return "\(done)/\(total) Today (\(percent)%)"
    }
    
    // MARK: - State & Toggle
    
    public func setEnabled(_ enable: Bool) {
        self.isEnabled = enable
        UserDefaults.standard.set(enable, forKey: keyEnabled)
        NotificationCenter.default.post(name: .habitTrackerStateDidChange, object: enable)
        
        if enable {
            showWindow()
        } else {
            closeWindow()
        }
    }
    
    public func toggleEnabled() {
        setEnabled(!isEnabled)
    }
    
    // MARK: - Window Management (Compact Single-Page HUD)
    
    public func toggleWindow() {
        if isWindowVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }
    
    public func showWindow() {
        if habitPanel == nil {
            setupPanel()
        }
        
        guard let panel = habitPanel else { return }
        
        // Position on main screen near center/top
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - panel.frame.width / 2
            let y = visible.midY - panel.frame.height / 2 + 30
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isWindowVisible = true
        
        if !isEnabled {
            isEnabled = true
            UserDefaults.standard.set(true, forKey: keyEnabled)
            NotificationCenter.default.post(name: .habitTrackerStateDidChange, object: true)
        }
    }
    
    public func closeWindow() {
        habitPanel?.orderOut(nil)
        isWindowVisible = false
    }
    
    private func setupPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 580)
        let panel = HabitTrackerPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.setContentSize(NSSize(width: 480, height: 580))
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hosting = NSHostingView(rootView: HabitTrackerView(service: self))
        panel.contentView = hosting
        self.habitPanel = panel
    }
    
    // MARK: - Bulletproof Persistence
    
    private func saveHabitsImmediate() {
        saveDebounceTimer?.invalidate()
        let items = habits
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(items)
                try data.write(to: self.storageFileURL, options: .atomic)
                try? data.write(to: self.mirrorFileURL, options: .atomic)
                UserDefaults.standard.set(data, forKey: self.keyBackup)
            } catch {
                NSLog("[HabitTrackerService] Save failed: %@", error.localizedDescription)
            }
        }
    }
    
    private func loadHabits() {
        // Tier 1: Primary File
        if let data = try? Data(contentsOf: storageFileURL),
           let loaded = try? JSONDecoder().decode([Habit].self, from: data) {
            self.habits = loaded
            return
        }
        
        // Tier 2: Mirror File
        if let data = try? Data(contentsOf: mirrorFileURL),
           let loaded = try? JSONDecoder().decode([Habit].self, from: data) {
            self.habits = loaded
            return
        }
        
        // Tier 3: UserDefaults Backup
        if let data = UserDefaults.standard.data(forKey: keyBackup),
           let loaded = try? JSONDecoder().decode([Habit].self, from: data) {
            self.habits = loaded
            return
        }
        
        // Tier 4: First-launch initial habits with sample tracking
        createInitialStarterHabits()
    }
    
    private func createInitialStarterHabits() {
        let calendar = Calendar.current
        let today = Date()
        
        var dateStrings: [String] = []
        for i in 0..<7 {
            if let d = calendar.date(byAdding: .day, value: -i, to: today) {
                dateStrings.append(Habit.dateFormatter.string(from: d))
            }
        }
        
        let sample1 = Habit(
            name: "Drink 2L Water",
            colorHex: "#06B6D4",
            icon: "💧",
            completedDates: Set(dateStrings.prefix(5))
        )
        
        let sample2 = Habit(
            name: "Daily Workout",
            colorHex: "#F97316",
            icon: "🏃",
            completedDates: Set(dateStrings.prefix(4))
        )
        
        let sample3 = Habit(
            name: "Read 20 Mins",
            colorHex: "#8B5CF6",
            icon: "📖",
            completedDates: Set(dateStrings.prefix(6))
        )
        
        let sample4 = Habit(
            name: "Mindfulness",
            colorHex: "#10B981",
            icon: "🧘",
            completedDates: Set(dateStrings.prefix(3))
        )
        
        self.habits = [sample1, sample2, sample3, sample4]
        saveHabitsImmediate()
    }
}

