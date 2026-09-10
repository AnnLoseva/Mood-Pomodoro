//
//  CheckIn.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

enum CheckInOrigin: String, Codable, Sendable {
    case scheduled
    case manual
}

@Model
final class CheckIn {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var moodRaw: String = Mood.neutral.rawValue
    var reason: String?
    var note: String?
    var session: FocusSession?
    /// Stored as `Data` rather than `[ConditionSnapshotEntry]` directly —
    /// SwiftData + CloudKit cannot reliably persist Codable arrays (empty
    /// `[]` traps in ModelCoders). The computed `conditionSnapshot` is the
    /// public surface.
    var conditionSnapshotJSON: Data = Data()

    /// Which conditions were active at `timestamp`, frozen at creation time.
    /// See `ConditionSnapshotEntry` for why this is a copy, not a live lookup.
    var conditionSnapshot: [ConditionSnapshotEntry] {
        get {
            guard !conditionSnapshotJSON.isEmpty else { return [] }
            return (try? JSONDecoder().decode([ConditionSnapshotEntry].self, from: conditionSnapshotJSON)) ?? []
        }
        set {
            conditionSnapshotJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    /// The originating notification/action's own identifier, set only for
    /// check-ins created from a notification mood action or a Live Activity
    /// intent. Lets the handler recognize "I already processed this exact
    /// action" and skip creating a duplicate if iOS redelivers the same
    /// interaction (double-tap, retry) — see `NotificationDelegate`.
    var sourceIdentifier: String?
    /// Shared across devices for a *scheduled* occurrence (`sessionID|epoch`).
    /// Nil for a manual "Как я сейчас" check-in, which is always a new record.
    var occurrenceID: String?
    var scheduledAt: Date?
    var originRaw: String = CheckInOrigin.manual.rawValue
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        mood: Mood,
        reason: String? = nil,
        note: String? = nil,
        conditionSnapshot: [ConditionSnapshotEntry] = [],
        sourceIdentifier: String? = nil,
        occurrenceID: String? = nil,
        scheduledAt: Date? = nil,
        origin: CheckInOrigin = .manual
    ) {
        self.id = id
        self.timestamp = timestamp
        self.moodRaw = mood.rawValue
        self.reason = reason
        self.note = note
        self.conditionSnapshot = conditionSnapshot
        self.sourceIdentifier = sourceIdentifier
        self.occurrenceID = occurrenceID
        self.scheduledAt = scheduledAt
        self.originRaw = origin.rawValue
        self.createdAt = timestamp
    }

    var origin: CheckInOrigin {
        get { CheckInOrigin(rawValue: originRaw) ?? .manual }
        set { originRaw = newValue.rawValue }
    }

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }
}
