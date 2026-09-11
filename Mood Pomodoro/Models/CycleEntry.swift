//
//  CycleEntry.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// What the user marked on a given day. Deliberately only two states — this
/// app records what the user tells it, it does not model or predict a cycle.
enum CycleEventKind: String, Codable, Sendable, CaseIterable {
    case periodStart
    /// "Menstruation continues today" — lets the user mark individual days
    /// (including ones remembered later) without implying a new start.
    case periodDay
    case periodEnd

    var label: String {
        switch self {
        case .periodStart: return L("Начало менструации", "Period started")
        case .periodDay: return L("Менструация продолжается", "Period continues")
        case .periodEnd: return L("Последний день менструации", "Last day of period")
        }
    }

    var icon: String {
        switch self {
        case .periodStart: return "🌸"
        case .periodDay: return "🌸"
        case .periodEnd: return "🍃"
        }
    }
}

/// One user-recorded cycle event, stored as a plain calendar day. Cycle day
/// for any date is derived from these (see `AnalyticsService.cycleDay`)
/// rather than stored, so correcting a mis-entered start date fixes every
/// day after it at once.
///
/// This is context for the user's own observations — never a medical record,
/// a diagnosis, or a prediction. Kept separate from the "Цикл" `FactorCategory`,
/// which stays what it is: a per-session condition tag.
@Model
final class CycleEntry {
    var id: UUID = UUID()
    /// Normalized to `startOfDay` — a cycle event is a day, not a moment.
    var date: Date = Date.now
    var kindRaw: String = CycleEventKind.periodStart.rawValue
    var note: String?
    /// When the mark was written — `date` is the day it is about.
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        date: Date,
        kind: CycleEventKind,
        note: String? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.date = calendar.startOfDay(for: date)
        self.kindRaw = kind.rawValue
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: CycleEventKind {
        get { CycleEventKind(rawValue: kindRaw) ?? .periodStart }
        set { kindRaw = newValue.rawValue }
    }
}
