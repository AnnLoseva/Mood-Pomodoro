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
    /// Energy and motivation at the same moment, both optional: a mood can
    /// always be logged on its own, and every check-in recorded before
    /// these existed simply has none. Optional (rather than defaulted) is
    /// also what keeps this a lightweight CloudKit migration — "не
    /// отмечено" has to stay a different answer from "средне".
    var energyRaw: String?
    var motivationRaw: String?
    /// Why the mood is what it is. Emotional only — why she does or doesn't
    /// want to carry on is `motivationReason`, a separate answer to a
    /// separate question.
    var reason: String?
    var motivationReason: String?
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
    /// When the record was written — *not* when the mood happened. A mood
    /// logged tonight about this morning has `timestamp` = morning,
    /// `createdAt` = tonight. Analytics only ever reads `timestamp`.
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        mood: Mood,
        energy: EnergyLevel? = nil,
        motivation: StudyMotivation? = nil,
        reason: String? = nil,
        motivationReason: String? = nil,
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
        self.energyRaw = energy?.rawValue
        self.motivationRaw = motivation?.rawValue
        self.reason = reason
        self.motivationReason = motivationReason
        self.note = note
        self.conditionSnapshot = conditionSnapshot
        self.sourceIdentifier = sourceIdentifier
        self.occurrenceID = occurrenceID
        self.scheduledAt = scheduledAt
        self.originRaw = origin.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var origin: CheckInOrigin {
        get { CheckInOrigin(rawValue: originRaw) ?? .manual }
        set { originRaw = newValue.rawValue }
    }

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }

    var energy: EnergyLevel? {
        get { energyRaw.flatMap(EnergyLevel.init(rawValue:)) }
        set { energyRaw = newValue?.rawValue }
    }

    var motivation: StudyMotivation? {
        get { motivationRaw.flatMap(StudyMotivation.init(rawValue:)) }
        set { motivationRaw = newValue?.rawValue }
    }

    /// One line naming whichever of the other two scales was answered, for
    /// a timeline row — empty when only a mood was recorded, so nothing is
    /// said about a question that wasn't asked.
    var levelsSummary: String? {
        var parts: [String] = []
        if let energy { parts.append("\(energy.emoji) \(energy.label)") }
        if let motivation {
            var text = "\(motivation.emoji) \(motivation.label)"
            if let motivationReason { text += " — \(Ldata(motivationReason))" }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
