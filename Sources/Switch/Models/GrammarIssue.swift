import Foundation
import SwiftUI

public enum GrammarCategory: String, CaseIterable, Identifiable, Sendable {
    case correctness = "Correctness"
    case clarity = "Clarity"
    case engagement = "Engagement"
    case delivery = "Delivery"
    
    public var id: String { rawValue }
    
    public var color: Color {
        switch self {
        case .correctness: return Color(red: 0.95, green: 0.32, blue: 0.35)
        case .clarity: return Color(red: 0.25, green: 0.60, blue: 0.98)
        case .engagement: return Color(red: 0.98, green: 0.72, blue: 0.20)
        case .delivery: return Color(red: 0.75, green: 0.40, blue: 0.95)
        }
    }
    
    public var icon: String {
        switch self {
        case .correctness: return "exclamationmark.circle.fill"
        case .clarity: return "drop.fill"
        case .engagement: return "sparkles"
        case .delivery: return "text.bubble.fill"
        }
    }
}

public struct GrammarIssue: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let category: GrammarCategory
    public let original: String
    public let replacement: String
    public let reason: String
    public let range: NSRange
    public var isApplied: Bool
    public var isDismissed: Bool
    
    public init(
        id: UUID = UUID(),
        category: GrammarCategory,
        original: String,
        replacement: String,
        reason: String,
        range: NSRange,
        isApplied: Bool = false,
        isDismissed: Bool = false
    ) {
        self.id = id
        self.category = category
        self.original = original
        self.replacement = replacement
        self.reason = reason
        self.range = range
        self.isApplied = isApplied
        self.isDismissed = isDismissed
    }
}
