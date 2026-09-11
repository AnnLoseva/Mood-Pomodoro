//
//  SupportEntry.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// What the user marked for a day's daily support (medication, vitamins —
/// the app never knows or names what it is). There is deliberately no
/// "missing" case here: a day with *no* `SupportEntry` means "не отмечено",
/// which is not the same thing as "не принято" — conflating the two would
/// turn every forgotten tap into a recorded skip.
enum SupportStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case taken
    case notTaken
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taken: return L("Принято", "Taken")
        case .notTaken: return L("Не принято", "Not taken")
        case .unknown: return L("Не помню", "Don't remember")
        }
    }

    var glyph: String {
        switch self {
        // Text-style check, not "☑" — iOS renders that as a grey emoji box
        // that doesn't match ✕ and ?.
        case .taken: return "✓"
        case .notTaken: return "✕"
        case .unknown: return "?"
        }
    }
}

/// One day's support mark. Tracking only — nothing in the app reminds,
/// recommends, or draws a medical conclusion from these.
///
/// `day` is the calendar day the mark is *about* (normalized to
/// `startOfDay`); `time` is optional because "принято в течение дня" is a
/// perfectly good answer. `createdAt`/`updatedAt` record when the user wrote
/// or last changed it — analytics never looks at those.
@Model
final class SupportEntry {
    var id: UUID = UUID()
    /// Lets a future second tracker live in the same table without a
    /// migration. The UI name is not stored — it isn't a hardcoded drug.
    var trackerKey: String = SupportEntry.defaultTrackerKey
    var day: Date = Date.now
    var time: Date?
    var statusRaw: String = SupportStatus.taken.rawValue
    var note: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    static let defaultTrackerKey = "daily-support"

    init(
        id: UUID = UUID(),
        day: Date,
        status: SupportStatus,
        time: Date? = nil,
        note: String? = nil,
        trackerKey: String = SupportEntry.defaultTrackerKey,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.trackerKey = trackerKey
        self.day = calendar.startOfDay(for: day)
        self.time = time
        self.statusRaw = status.rawValue
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    var status: SupportStatus {
        get { SupportStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }
}
