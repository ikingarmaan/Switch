import Foundation
import Cocoa
import SwiftUI
import Combine

public extension Notification.Name {
    static let selfControlStateDidChange = Notification.Name("SwitchSelfControlStateDidChange")
    static let selfControlTick = Notification.Name("SwitchSelfControlTick")
}

public struct SelfControlCheckIn: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let intensity: Int // 1-10
    public let triggers: [String]
    public let notes: String
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), intensity: Int, triggers: [String], notes: String) {
        self.id = id
        self.timestamp = timestamp
        self.intensity = intensity
        self.triggers = triggers
        self.notes = notes
    }
}

public struct StreakHistoryRecord: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public let startDate: Date
    public let endDate: Date
    public let durationDays: Double
    public let trigger: String
    
    public init(id: UUID = UUID(), startDate: Date, endDate: Date, durationDays: Double, trigger: String) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.durationDays = durationDays
        self.trigger = trigger
    }
}

public final class SelfControlService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = SelfControlService()
    
    // UserDefaults Keys
    private let keyStartDate = "switch.selfControl.startDate"
    private let keyUrgesResisted = "switch.selfControl.urgesResisted"
    private let keyShieldActive = "switch.selfControl.shieldActive"
    private let keyPersonalReasons = "switch.selfControl.personalReasons"
    private let keyCheckins = "switch.selfControl.checkins"
    private let keyHistory = "switch.selfControl.history"
    
    @Published public private(set) var startDate: Date = Date()
    @Published public private(set) var urgesResisted: Int = 0
    @Published public private(set) var isShieldActive: Bool = false
    @Published public var personalReasons: [String] = []
    @Published public var checkins: [SelfControlCheckIn] = []
    @Published public var streakHistory: [StreakHistoryRecord] = []
    
    // Live timer
    @Published public private(set) var elapsedSeconds: Int = 0
    private var secondTimer: Timer?
    
    override private init() {
        super.init()
        loadData()
        startLiveTimer()
    }
    
    private func loadData() {
        let defaults = UserDefaults.standard
        
        // Start date
        if let savedDate = defaults.object(forKey: keyStartDate) as? Date {
            self.startDate = savedDate
        } else {
            let now = Date()
            self.startDate = now
            defaults.set(now, forKey: keyStartDate)
        }
        
        // Urges resisted
        self.urgesResisted = defaults.integer(forKey: keyUrgesResisted)
        
        // Shield active
        self.isShieldActive = defaults.bool(forKey: keyShieldActive)
        
        // Reasons
        if let reasons = defaults.stringArray(forKey: keyPersonalReasons), !reasons.isEmpty {
            self.personalReasons = reasons
        } else {
            self.personalReasons = [
                "Regain mental clarity, focus, and deep dopamine sensitivity",
                "Restore natural intimacy and heal pornography-induced numbness",
                "Reclaim lost hours and end the exhausting shame cycle",
                "Build unwavering self-trust and respect who I see in the mirror"
            ]
            defaults.set(self.personalReasons, forKey: keyPersonalReasons)
        }
        
        // Checkins
        if let data = defaults.data(forKey: keyCheckins),
           let decoded = try? JSONDecoder().decode([SelfControlCheckIn].self, from: data) {
            self.checkins = decoded
        }
        
        // History
        if let data = defaults.data(forKey: keyHistory),
           let decoded = try? JSONDecoder().decode([StreakHistoryRecord].self, from: data) {
            self.streakHistory = decoded
        }
    }
    
    private func startLiveTimer() {
        updateElapsed()
        secondTimer?.invalidate()
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateElapsed()
            }
        }
    }
    
    private func updateElapsed() {
        let diff = max(0, Int(Date().timeIntervalSince(startDate)))
        self.elapsedSeconds = diff
        NotificationCenter.default.post(name: .selfControlTick, object: statusSubtitle)
    }
    
    // MARK: - Computed Properties
    
    public var daysClean: Double {
        return Double(elapsedSeconds) / 86400.0
    }
    
    public var daysInt: Int {
        return elapsedSeconds / 86400
    }
    
    public var hoursInt: Int {
        return (elapsedSeconds % 86400) / 3600
    }
    
    public var minutesInt: Int {
        return (elapsedSeconds % 3600) / 60
    }
    
    public var secondsInt: Int {
        return elapsedSeconds % 60
    }
    
    public var rebootPercentage: Double {
        return min(100.0, max(0.0, (daysClean / 90.0) * 100.0))
    }
    
    public var formattedStreak: String {
        if daysInt > 0 {
            return "\(daysInt)d \(hoursInt)h \(minutesInt)m"
        } else if hoursInt > 0 {
            return "\(hoursInt)h \(minutesInt)m \(secondsInt)s"
        } else {
            return "\(minutesInt)m \(secondsInt)s"
        }
    }
    
    public var statusSubtitle: String {
        let streakStr: String
        if daysInt > 0 {
            streakStr = "\(daysInt)d clean"
        } else if hoursInt > 0 {
            streakStr = "\(hoursInt)h clean"
        } else {
            streakStr = "\(minutesInt)m clean"
        }
        
        if isShieldActive {
            return "🔥 \(streakStr) • Shield ON"
        } else {
            return "🔥 \(streakStr)"
        }
    }
    
    public var longestStreakDays: Double {
        var longest = daysClean
        for h in streakHistory {
            if h.durationDays > longest {
                longest = h.durationDays
            }
        }
        return longest
    }
    
    public var currentPhaseTitle: String {
        let d = daysClean
        if d < 3.0 {
            return "Phase 1: Acute Dopamine Reset (Days 1–3)"
        } else if d < 7.0 {
            return "Phase 2: Androgen Surge (Days 4–7)"
        } else if d < 14.0 {
            return "Phase 3: Prefrontal Awakening (Days 8–14)"
        } else if d < 30.0 {
            return "Phase 4: Fog Clearing & Libido Rest (Days 15–30)"
        } else if d < 60.0 {
            return "Phase 5: Deep Neural Rewiring (Days 31–60)"
        } else {
            return "Phase 6: Baseline Freedom (Days 61–90+)"
        }
    }
    
    // MARK: - Actions
    
    public func setShield(_ active: Bool) {
        guard active != isShieldActive else { return }
        self.isShieldActive = active
        UserDefaults.standard.set(active, forKey: keyShieldActive)
        
        if active {
            // Apply Family DNS profile to block adult content Mac-wide
            DNSService.shared.applyProfile(.family)
        } else {
            // Restore default
            DNSService.shared.setEnabled(false)
        }
        
        NotificationCenter.default.post(name: .selfControlStateDidChange, object: active)
    }
    
    public func toggleShield() {
        setShield(!isShieldActive)
    }
    
    public func logUrgeVictory(trigger: String = "Urge Resisted") {
        self.urgesResisted += 1
        UserDefaults.standard.set(self.urgesResisted, forKey: keyUrgesResisted)
        
        let checkin = SelfControlCheckIn(
            intensity: 7,
            triggers: [trigger],
            notes: "Victory recorded! Resisted impulse and chose self-mastery."
        )
        self.checkins.insert(checkin, at: 0)
        saveCheckins()
        
        NotificationCenter.default.post(name: .selfControlStateDidChange, object: nil)
    }
    
    public func logCheckIn(intensity: Int, triggers: [String], notes: String) {
        let checkin = SelfControlCheckIn(
            intensity: intensity,
            triggers: triggers,
            notes: notes
        )
        self.checkins.insert(checkin, at: 0)
        if self.checkins.count > 200 {
            self.checkins = Array(self.checkins.prefix(200))
        }
        saveCheckins()
    }
    
    private func saveCheckins() {
        if let encoded = try? JSONEncoder().encode(self.checkins) {
            UserDefaults.standard.set(encoded, forKey: keyCheckins)
        }
    }
    
    public func resetStreak(trigger: String) {
        let endedDuration = daysClean
        let record = StreakHistoryRecord(
            startDate: self.startDate,
            endDate: Date(),
            durationDays: endedDuration,
            trigger: trigger
        )
        self.streakHistory.insert(record, at: 0)
        if self.streakHistory.count > 100 {
            self.streakHistory = Array(self.streakHistory.prefix(100))
        }
        if let encoded = try? JSONEncoder().encode(self.streakHistory) {
            UserDefaults.standard.set(encoded, forKey: keyHistory)
        }
        
        let now = Date()
        self.startDate = now
        UserDefaults.standard.set(now, forKey: keyStartDate)
        updateElapsed()
        
        NotificationCenter.default.post(name: .selfControlStateDidChange, object: nil)
    }
    
    public func setCustomStartDate(_ date: Date) {
        self.startDate = date
        UserDefaults.standard.set(date, forKey: keyStartDate)
        updateElapsed()
        NotificationCenter.default.post(name: .selfControlStateDidChange, object: nil)
    }
    
    public func addReason(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.personalReasons.append(trimmed)
        UserDefaults.standard.set(self.personalReasons, forKey: keyPersonalReasons)
    }
    
    public func removeReason(at index: Int) {
        guard index >= 0 && index < personalReasons.count else { return }
        self.personalReasons.remove(at: index)
        UserDefaults.standard.set(self.personalReasons, forKey: keyPersonalReasons)
    }
}
