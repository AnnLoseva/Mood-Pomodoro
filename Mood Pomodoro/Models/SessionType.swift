//
//  SessionType.swift
//  Mood Pomodoro
//

import SwiftUI

/// What a session *was*, as opposed to what it was called. A separate field
/// from `FocusSession.activity` on purpose: программирование can be учёба on
/// Monday, обязательная работа on Tuesday and отдых on Sunday, and the name
/// alone can never say which.
///
/// There are exactly three, and none of them is a default: a session with no
/// type is "нераспределённая", which is a *state of older data*, not a
/// fourth kind to create. See `FocusSession.sessionType`.
enum SessionType: String, Codable, Sendable, CaseIterable, Identifiable {
    case rest
    case obligatoryWork
    case study

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rest: return L("Отдых", "Rest")
        case .obligatoryWork: return L("Обязательная работа", "Obligatory work")
        case .study: return L("Учёба", "Study")
        }
    }

    /// Short enough for a chart legend or a narrow chip.
    var shortLabel: String {
        switch self {
        case .rest: return L("Отдых", "Rest")
        case .obligatoryWork: return L("Работа", "Work")
        case .study: return L("Учёба", "Study")
        }
    }

    var emoji: String {
        switch self {
        case .rest: return "🌿"
        case .obligatoryWork: return "🧾"
        case .study: return "📚"
        }
    }

    /// One colour per type, reused by every chart and chip so a band means
    /// the same thing wherever it is drawn.
    var color: Color {
        switch self {
        case .rest: return AppTheme.moss
        case .obligatoryWork: return Color(red: 0.357, green: 0.463, blue: 0.541)
        case .study: return Color(red: 0.769, green: 0.584, blue: 0.259)
        }
    }

    /// What an untyped session is called. Named here rather than added as a
    /// case so it can never be picked when creating one.
    static var unassignedLabel: String { L("Без типа", "No type yet") }
    static var unassignedColor: Color { AppTheme.border }
    static var unassignedEmoji: String { "•" }

    /// Label for an optional type, with the "not chosen yet" state spelled
    /// out — used by every summary row that groups by type.
    static func label(for type: SessionType?) -> String { type?.label ?? unassignedLabel }
    static func color(for type: SessionType?) -> Color { type?.color ?? unassignedColor }
    static func emoji(for type: SessionType?) -> String { type?.emoji ?? unassignedEmoji }
}
