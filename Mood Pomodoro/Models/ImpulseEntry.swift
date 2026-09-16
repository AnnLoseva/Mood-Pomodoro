//
//  ImpulseEntry.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// What the impulse was about. Three drawers, nothing more — the app never
/// decides for itself that a meal, a purchase or a new activity was
/// impulsive: that is a mark the user makes, and only she makes it.
enum ImpulseCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case food
    case purchase
    case newActivity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: return L("Еда", "Food")
        case .purchase: return L("Покупки", "Shopping")
        case .newActivity: return L("Новое занятие", "New activity")
        }
    }

    var emoji: String {
        switch self {
        case .food: return "🍽"
        case .purchase: return "🛍"
        case .newActivity: return "🌱"
        }
    }

    /// No artwork of its own — the impulse rows use the category emoji, and
    /// a made-up asset name would render as a blank square.
    var symbolName: String {
        switch self {
        case .food: return "fork.knife"
        case .purchase: return "bag"
        case .newActivity: return "sparkles"
        }
    }
}

/// How strong the pull was, when she wanted to say. Optional on every
/// record — the minimum an impulse needs is a category and a time.
enum ImpulseStrength: String, ScaleStep {
    case veryStrong
    case strong
    case medium
    case mild
    case veryMild

    var id: String { rawValue }

    static var orderedCases: [ImpulseStrength] { [.veryStrong, .strong, .medium, .mild, .veryMild] }

    var scale: Double {
        switch self {
        case .veryStrong: return 5
        case .strong: return 4
        case .medium: return 3
        case .mild: return 2
        case .veryMild: return 1
        }
    }

    var label: String {
        switch self {
        case .veryStrong: return L("Очень сильный", "Very strong")
        case .strong: return L("Сильный", "Strong")
        case .medium: return L("Средний", "Medium")
        case .mild: return L("Слабый", "Mild")
        case .veryMild: return L("Едва заметный", "Barely there")
        }
    }

    var emoji: String {
        switch self {
        case .veryStrong: return "🌊"
        case .strong: return "💨"
        case .medium: return "🍂"
        case .mild: return "🪶"
        case .veryMild: return "·"
        }
    }
}

/// Whether it stayed a wish. Two plainly-worded answers, neither of which
/// the app treats as better than the other.
enum ImpulseOutcome: String, Codable, Sendable, CaseIterable, Identifiable {
    case wanted
    case acted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wanted: return L("Только захотелось", "Just felt like it")
        case .acted: return L("Сделала", "Did it")
        }
    }

    var emoji: String {
        switch self {
        case .wanted: return "💭"
        case .acted: return "✔️"
        }
    }
}

/// One impulse, marked by the user.
///
/// The record is deliberately cheap: a category and the moment it happened
/// are enough, and every other field stays nil until she fills it in — the
/// app never guesses a strength, never assumes she acted, and never writes
/// one of these by itself. It is also **not** a meal or a session: marking
/// "импульсивно поела" here creates no `FoodEntry` and no `FocusSession`,
/// so nothing is counted twice.
///
/// An absence of these records means impulses weren't written down — never
/// that there weren't any.
@Model
final class ImpulseEntry {
    var id: UUID = UUID()
    var eventDate: Date = Date.now
    var categoryRaw: String = ImpulseCategory.food.rawValue
    var strengthRaw: String?
    var outcomeRaw: String?
    var note: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        eventDate: Date,
        category: ImpulseCategory,
        strength: ImpulseStrength? = nil,
        outcome: ImpulseOutcome? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.eventDate = eventDate
        self.categoryRaw = category.rawValue
        self.strengthRaw = strength?.rawValue
        self.outcomeRaw = outcome?.rawValue
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    var category: ImpulseCategory {
        get { ImpulseCategory(rawValue: categoryRaw) ?? .food }
        set { categoryRaw = newValue.rawValue }
    }

    var strength: ImpulseStrength? {
        get { strengthRaw.flatMap(ImpulseStrength.init(rawValue:)) }
        set { strengthRaw = newValue?.rawValue }
    }

    var outcome: ImpulseOutcome? {
        get { outcomeRaw.flatMap(ImpulseOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    /// "Сделала · сильный" — only what was actually answered.
    var detailLine: String {
        var parts: [String] = []
        if let outcome { parts.append(outcome.label) }
        if let strength { parts.append(L("сила: \(strength.label.lowercased())", "strength: \(strength.label.lowercased())")) }
        return parts.joined(separator: " · ")
    }
}
