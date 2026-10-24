import SwiftUI

// MARK: - View State (No @State macro to avoid SwiftUIMacros compiler issues)
public final class HabitTrackerViewState: ObservableObject {
    @Published public var selectedTab: HabitTrackerTab = .week
    @Published public var isAddingHabit: Bool = false
    @Published public var newHabitName: String = ""
    @Published public var newHabitColor: String = HabitColors.presets[0].hex
    @Published public var newHabitIcon: String = "⚡️"
    @Published public var displayedMonth: Date = Date()
    @Published public var selectedDateForInspection: Date? = Date()
    
    public init() {}
}

public enum HabitTrackerTab: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Monthly Calendar"
    
    public var id: String { rawValue }
}

public struct HabitTrackerView: View {
    @ObservedObject var service: HabitTrackerService
    @StateObject private var state = HabitTrackerViewState()
    
    // Quick icon options
    private let iconOptions = ["💧", "🏃", "📖", "🧘", "💪", "💻", "🥗", "💤", "🎯", "⚡️", "✍️", "☕️"]
    
    public init(service: HabitTrackerService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top Header Bar
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                
                Divider()
                    .background(Color.white.opacity(0.12))
                
                // Add Habit Collapsible Panel
                if state.isAddingHabit {
                    addHabitSection
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                }
                
                // Main Content (Single Page Compact Scroll)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Quick Stats Pill
                        statsSummaryCard
                        
                        // Switch between Week & Month
                        if state.selectedTab == .week {
                            weekMatrixSection
                        } else {
                            monthCalendarSection
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 480, height: 580)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.16, green: 0.82, blue: 0.54))
            
            Text("Habit Tracker")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            // Tab Picker
            Picker("", selection: $state.selectedTab) {
                ForEach(HabitTrackerTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            
            // Add Habit Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.isAddingHabit.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: state.isAddingHabit ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(state.isAddingHabit ? "Close" : "Add")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(state.isAddingHabit ? Color.white.opacity(0.15) : Color(red: 0.16, green: 0.82, blue: 0.54))
                )
            }
            .buttonStyle(.plain)
            
            // Close Window Button
            Button(action: {
                service.closeWindow()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Close Habit Tracker")
        }
    }
    
    // MARK: - Stats Summary Card
    
    private var statsSummaryCard: some View {
        let (todayDone, total) = service.todayCompletionRatio
        let todayPercent = total > 0 ? Int((Double(todayDone) / Double(total)) * 100) : 0
        let weekDates = currentWeekDates()
        let weekDone = service.habits.reduce(0) { $0 + $1.weeklyCount(for: weekDates) }
        let maxWeek = service.habits.count * 7
        let weekPercent = maxWeek > 0 ? Int((Double(weekDone) / Double(maxWeek)) * 100) : 0
        
        return HStack(spacing: 12) {
            // Today Stat
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(todayDone) / CGFloat(total) : 0)
                        .stroke(Color(red: 0.16, green: 0.82, blue: 0.54), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 32, height: 32)
                    Text("\(todayPercent)%")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today's Focus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.9))
                    Text("\(todayDone) of \(total) done")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
            
            // Week Stat
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.98, green: 0.56, blue: 0.18))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(red: 0.98, green: 0.56, blue: 0.18).opacity(0.15)))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Week Adherence")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.9))
                    Text("\(weekPercent)% followed")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
            
            // Active Habits Count
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.15)))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tracking")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.9))
                    Text("\(service.habits.count) habits")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
        }
    }
    
    // MARK: - Week Matrix View
    
    private var weekMatrixSection: some View {
        let dates = currentWeekDates()
        let todayStr = Habit.dateFormatter.string(from: Date())
        
        return VStack(spacing: 12) {
            // Days Header
            HStack(spacing: 0) {
                Text("HABIT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.gray.opacity(0.8))
                    .frame(width: 170, alignment: .leading)
                
                HStack(spacing: 7) {
                    ForEach(dates, id: \.self) { date in
                        let dateStr = Habit.dateFormatter.string(from: date)
                        let isToday = dateStr == todayStr
                        
                        VStack(spacing: 2) {
                            Text(weekdayInitial(from: date))
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(isToday ? Color(red: 0.16, green: 0.82, blue: 0.54) : Color.gray.opacity(0.8))
                            Text(dayOfMonth(from: date))
                                .font(.system(size: 10.5, weight: isToday ? .bold : .medium, design: .rounded))
                                .foregroundColor(isToday ? .white : Color.gray.opacity(0.7))
                        }
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isToday ? Color.white.opacity(0.12) : Color.clear)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            
            // Habit Rows
            if service.habits.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 28))
                        .foregroundColor(Color.gray.opacity(0.5))
                        .padding(.top, 20)
                    Text("No habits added yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                    Button(action: { state.isAddingHabit = true }) {
                        Text("+ Add First Habit")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.16, green: 0.82, blue: 0.54))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }
            } else {
                ForEach(service.habits) { habit in
                    habitWeekRow(habit: habit, dates: dates, todayStr: todayStr)
                }
            }
        }
    }
    
    private func habitWeekRow(habit: Habit, dates: [Date], todayStr: String) -> some View {
        let habitColor = HabitColors.color(from: habit.colorHex)
        let weekCompleted = habit.weeklyCount(for: dates)
        
        return HStack(spacing: 0) {
            // Left info: Icon, Name, Streak
            HStack(spacing: 7) {
                Text(habit.icon)
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(habitColor)
                            .frame(width: 6, height: 6)
                        Text("\(weekCompleted)/7 this week")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.gray.opacity(0.9))
                        if habit.currentStreak > 0 {
                            Text("· 🔥 \(habit.currentStreak)d")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(Color(red: 0.98, green: 0.56, blue: 0.18))
                        }
                    }
                }
            }
            .frame(width: 170, alignment: .leading)
            
            // Right: 7 interactive circular check buttons
            HStack(spacing: 7) {
                ForEach(dates, id: \.self) { date in
                    let dateStr = Habit.dateFormatter.string(from: date)
                    let isDone = habit.isCompleted(dateStr: dateStr)
                    let isToday = dateStr == todayStr
                    
                    Button(action: {
                        service.toggleCompletion(habitId: habit.id, dateStr: dateStr)
                    }) {
                        ZStack {
                            Circle()
                                .fill(isDone ? habitColor : (isToday ? Color.white.opacity(0.08) : Color.white.opacity(0.03)))
                                .frame(width: 27, height: 27)
                            
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.white)
                            } else {
                                Circle()
                                    .stroke(isToday ? habitColor.opacity(0.7) : Color.white.opacity(0.15), lineWidth: 1.2)
                                    .frame(width: 27, height: 27)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.04))
        )
        .contextMenu {
            Button(role: .destructive, action: {
                service.deleteHabit(id: habit.id)
            }) {
                HStack {
                    Text("Delete Habit")
                    Image(systemName: "trash")
                }
            }
        }
    }
    
    // MARK: - Monthly Calendar Section
    
    private var monthCalendarSection: some View {
        VStack(spacing: 14) {
            // Month Switcher Header
            HStack {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.gray.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(monthYearString(from: state.displayedMonth))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { state.displayedMonth = Date(); state.selectedDateForInspection = Date() }) {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.16, green: 0.82, blue: 0.54))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.gray.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            
            // Month Calendar Grid
            monthCalendarGrid
            
            // Selected Day Inspection / Quick Check-off
            if let selected = state.selectedDateForInspection {
                selectedDayInspector(date: selected)
            }
            
            // Monthly Adherence Breakdown Per Habit
            monthlyHabitBreakdownCard
        }
    }
    
    private var monthCalendarGrid: some View {
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: state.displayedMonth)?.count ?? 30
        let components = calendar.dateComponents([.year, .month], from: state.displayedMonth)
        let firstOfMonth = calendar.date(from: components)!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday
        let todayStr = Habit.dateFormatter.string(from: Date())
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        let weekdayNames = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        
        return VStack(spacing: 6) {
            // Weekday Headers
            HStack(spacing: 5) {
                ForEach(weekdayNames, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.gray.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            
            // Grid of Days
            LazyVGrid(columns: columns, spacing: 5) {
                // Leading empty spaces for offset
                ForEach(0..<(firstWeekday - 1), id: \.self) { _ in
                    Color.clear
                        .frame(height: 38)
                }
                
                // Days of month
                ForEach(1...daysInMonth, id: \.self) { day in
                    let cellDate: Date = {
                        var dayComponents = components
                        dayComponents.day = day
                        return calendar.date(from: dayComponents) ?? state.displayedMonth
                    }()
                    let dateStr = Habit.dateFormatter.string(from: cellDate)
                    let isToday = dateStr == todayStr
                    let isSelected = state.selectedDateForInspection != nil && Habit.dateFormatter.string(from: state.selectedDateForInspection!) == dateStr
                    let completedHabits = service.habits.filter { $0.isCompleted(dateStr: dateStr) }
                    
                    HabitCalendarDayCell(
                        day: day,
                        cellDate: cellDate,
                        isToday: isToday,
                        isSelected: isSelected,
                        completedHabits: completedHabits
                    ) {
                        state.selectedDateForInspection = cellDate
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
    
    private func selectedDayInspector(date: Date) -> some View {
        let dateStr = Habit.dateFormatter.string(from: date)
        let df = DateFormatter()
        df.dateStyle = .medium
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Habits for \(df.string(from: date))")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                let completedCount = service.habits.filter { $0.isCompleted(dateStr: dateStr) }.count
                Text("\(completedCount)/\(service.habits.count) done")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.16, green: 0.82, blue: 0.54))
            }
            
            // Horizontal list of habits for quick check-off on this date
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.habits) { habit in
                        let isDone = habit.isCompleted(dateStr: dateStr)
                        let habitColor = HabitColors.color(from: habit.colorHex)
                        
                        Button(action: {
                            service.toggleCompletion(habitId: habit.id, dateStr: dateStr)
                        }) {
                            HStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(isDone ? habitColor : Color.white.opacity(0.1))
                                        .frame(width: 16, height: 16)
                                    if isDone {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .black))
                                            .foregroundColor(.white)
                                    }
                                }
                                Text("\(habit.icon) \(habit.name)")
                                    .font(.system(size: 11, weight: isDone ? .semibold : .regular))
                                    .foregroundColor(isDone ? .white : Color.gray.opacity(0.9))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDone ? habitColor.opacity(0.18) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isDone ? habitColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
    
    private var monthlyHabitBreakdownCard: some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: state.displayedMonth)
        let month = calendar.component(.month, from: state.displayedMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: state.displayedMonth)?.count ?? 30
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("MONTHLY PROGRESS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.gray.opacity(0.8))
            
            ForEach(service.habits) { habit in
                let count = habit.monthlyCount(year: year, month: month)
                let percent = habit.monthlyPercentage(year: year, month: month, daysInMonth: daysInMonth)
                let habitColor = HabitColors.color(from: habit.colorHex)
                
                VStack(spacing: 4) {
                    HStack {
                        Text("\(habit.icon) \(habit.name)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text("\(count) / \(daysInMonth) days (\(Int(percent))%)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(habitColor)
                    }
                    
                    // Custom Colored Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(habitColor)
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, percent / 100.0))), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
    
    // MARK: - Add Habit Inline Panel
    
    private var addHabitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New Habit")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Cancel") {
                    withAnimation { state.isAddingHabit = false }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            }
            
            // Name Field
            TextField("Habit name (e.g. 10k Steps, Reading, Deep Work)...", text: $state.newHabitName)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(.white)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            
            // Emoji Selector
            HStack(spacing: 8) {
                Text("Icon:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button(action: { state.newHabitIcon = icon }) {
                                Text(icon)
                                    .font(.system(size: 14))
                                    .frame(width: 26, height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(state.newHabitIcon == icon ? Color.white.opacity(0.2) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Color Selector
            HStack(spacing: 8) {
                Text("Color:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                    ForEach(HabitColors.presets) { preset in
                        Button(action: { state.newHabitColor = preset.hex }) {
                            ZStack {
                                Circle()
                                    .fill(HabitColors.color(from: preset.hex))
                                    .frame(width: 20, height: 20)
                                
                                if state.newHabitColor == preset.hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Submit Button
            Button(action: saveNewHabit) {
                HStack {
                    Spacer()
                    Text("Create Habit")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.16, green: 0.82, blue: 0.54))
                )
            }
            .buttonStyle(.plain)
            .disabled(state.newHabitName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(state.newHabitName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
    }
    
    private func saveNewHabit() {
        guard !state.newHabitName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        service.addHabit(name: state.newHabitName, colorHex: state.newHabitColor, icon: state.newHabitIcon)
        state.newHabitName = ""
        withAnimation {
            state.isAddingHabit = false
        }
    }
    
    // MARK: - Date Helpers
    
    private func currentWeekDates() -> [Date] {
        let calendar = Calendar.current
        let today = Date()
        // Get the start of the current week (Monday)
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        components.weekday = 2 // Monday in Gregorian
        let startOfWeek = calendar.date(from: components) ?? today
        
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }
    
    private func weekdayInitial(from date: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let initials = ["S", "M", "T", "W", "T", "F", "S"]
        return initials[(weekday - 1) % 7]
    }
    
    private func dayOfMonth(from date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.day, from: date))"
    }
    
    private func monthYearString(from date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df.string(from: date)
    }
    
    private func changeMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: state.displayedMonth) {
            state.displayedMonth = next
            state.selectedDateForInspection = next
        }
    }
}

// MARK: - Extracted Calendar Day Cell (Optimized for Swift Type-Checker)
struct HabitCalendarDayCell: View {
    let day: Int
    let cellDate: Date
    let isToday: Bool
    let isSelected: Bool
    let completedHabits: [Habit]
    let onSelect: () -> Void
    
    private var textColor: Color {
        if isToday {
            return Color(red: 0.16, green: 0.82, blue: 0.54)
        } else if isSelected {
            return .white
        } else {
            return Color.white.opacity(0.85)
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.18)
        } else if isToday {
            return Color.white.opacity(0.08)
        } else {
            return Color.white.opacity(0.02)
        }
    }
    
    private var borderColor: Color {
        if isToday {
            return Color(red: 0.16, green: 0.82, blue: 0.54).opacity(0.8)
        } else if isSelected {
            return Color.white.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundColor(textColor)
                
                HStack(spacing: 2.5) {
                    ForEach(completedHabits.prefix(4)) { habit in
                        Circle()
                            .fill(HabitColors.color(from: habit.colorHex))
                            .frame(width: 4.5, height: 4.5)
                    }
                    if completedHabits.count > 4 {
                        Circle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 7).fill(backgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
