import Foundation
import SwiftUI

public struct HabitColorPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let hex: String
    
    public init(name: String, hex: String) {
        self.id = hex
        self.name = name
        self.hex = hex
    }
}

public enum HabitColors {
    public static let presets: [HabitColorPreset] = [
        HabitColorPreset(name: "Emerald Green", hex: "#10B981"),
        HabitColorPreset(name: "Electric Blue", hex: "#3B82F6"),
        HabitColorPreset(name: "Sunset Orange", hex: "#F97316"),
        HabitColorPreset(name: "Neon Purple", hex: "#8B5CF6"),
        HabitColorPreset(name: "Coral Pink", hex: "#EC4899"),
        HabitColorPreset(name: "Golden Amber", hex: "#F59E0B"),
        HabitColorPreset(name: "Cyan Aqua", hex: "#06B6D4"),
        HabitColorPreset(name: "Rose Red", hex: "#EF4444")
    ]
    
    public static func color(from hex: String) -> Color {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return Color(red: 0.06, green: 0.73, blue: 0.51) // fallback emerald
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var icon: String
    public var completedDates: Set<String> // Stored as "YYYY-MM-DD"
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#10B981",
        icon: String = "⚡️",
        completedDates: Set<String> = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.completedDates = completedDates
        self.createdAt = createdAt
    }
    
    // Custom decoder for bulletproof backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Habit"
        self.colorHex = (try? container.decodeIfPresent(String.self, forKey: .colorHex)) ?? "#10B981"
        self.icon = (try? container.decodeIfPresent(String.self, forKey: .icon)) ?? "⚡️"
        let datesArray = (try? container.decodeIfPresent([String].self, forKey: .completedDates)) ?? []
        self.completedDates = Set(datesArray)
        self.createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(icon, forKey: .icon)
        try container.encode(Array(completedDates), forKey: .completedDates)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex, icon, completedDates, createdAt
    }
    
    // MARK: - Date Helpers
    
    public static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    public func isCompleted(on date: Date) -> Bool {
        let key = Habit.dateFormatter.string(from: date)
        return completedDates.contains(key)
    }
    
    public func isCompleted(dateStr: String) -> Bool {
        return completedDates.contains(dateStr)
    }
    
    public mutating func toggle(date: Date) {
        let key = Habit.dateFormatter.string(from: date)
        toggle(dateStr: key)
    }
    
    public mutating func toggle(dateStr: String) {
        if completedDates.contains(dateStr) {
            completedDates.remove(dateStr)
        } else {
            completedDates.insert(dateStr)
        }
    }
    
    // MARK: - Weekly & Monthly Stats
    
    public func weeklyCount(for dates: [Date]) -> Int {
        dates.filter { isCompleted(on: $0) }.count
    }
    
    public func monthlyCount(year: Int, month: Int) -> Int {
        let prefix = String(format: "%04d-%02d-", year, month)
        return completedDates.filter { $0.hasPrefix(prefix) }.count
    }
    
    public func monthlyPercentage(year: Int, month: Int, daysInMonth: Int) -> Double {
        guard daysInMonth > 0 else { return 0 }
        let count = monthlyCount(year: year, month: month)
        return min(100.0, (Double(count) / Double(daysInMonth)) * 100.0)
    }
    
    /// Current consecutive day streak leading up to today (or yesterday)
    public var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        
        // If today is completed, start from today. If not yet done today, check if yesterday was done
        if isCompleted(on: checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return streak }
            checkDate = prev
        } else {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            if !isCompleted(on: yesterday) {
                return 0
            }
            checkDate = yesterday
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return streak }
            checkDate = prev
        }
        
        while isCompleted(on: checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        
        return streak
    }
}

