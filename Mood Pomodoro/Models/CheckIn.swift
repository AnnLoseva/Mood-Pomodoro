//
//  CheckIn.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

@Model
final class CheckIn {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var moodRaw: String
    var reason: String?
    var note: String?
    var session: FocusSession?
    /// Which conditions were active at `timestamp`, frozen at creation time.
    /// See `ConditionSnapshotEntry` for why this is a copy, not a live lookup.
    var conditionSnapshot: [ConditionSnapshotEntry] = []

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        mood: Mood,
        reason: String? = nil,
        note: String? = nil,
        conditionSnapshot: [ConditionSnapshotEntry] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.moodRaw = mood.rawValue
        self.reason = reason
        self.note = note
        self.conditionSnapshot = conditionSnapshot
    }

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }
}
