//
//  EmotionEntry.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// One moment's emotions, as their own record.
///
/// Three things this model is careful about, all of them requirements
/// rather than taste:
/// * **It stands alone.** An emotion never needs a session, and never needs
///   a mood/energy/motivation answer to exist — the app must not invent a
///   neutral `CheckIn` just to hang a feeling off.
/// * **Empty means nothing was said.** A record with no emotions is not
///   "спокойно"; the form refuses to save one, and readers skip any that
///   sync leaves behind.
/// * **Several at once are normal.** "Тревожная и злая" is one moment, not
///   two records, so the selection is a set.
///
/// Same date discipline as every other diary record: `eventDate` is when the
/// feeling was, `createdAt` when the line was typed. Analytics only ever
/// reads `eventDate`.
@Model
final class EmotionEntry {
    var id: UUID = UUID()
    var eventDate: Date = Date.now
    /// Raw values joined by "|". A plain `String` rather than `[Emotion]`
    /// for the same reason `CheckIn.conditionSnapshotJSON` is `Data`:
    /// SwiftData + CloudKit does not reliably persist collection-typed
    /// attributes. `emotions` below is the public surface.
    var emotionsRaw: String = ""
    var note: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        eventDate: Date,
        emotions: [Emotion],
        note: String? = nil
    ) {
        self.id = id
        self.eventDate = eventDate
        self.emotionsRaw = Self.encode(emotions)
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Stored in the enum's own order, de-duplicated, so two records of the
    /// same feelings always read the same way.
    var emotions: [Emotion] {
        get {
            let stored = Set(emotionsRaw.split(separator: "|").compactMap { Emotion(rawValue: String($0)) })
            return Emotion.allCases.filter(stored.contains)
        }
        set { emotionsRaw = Self.encode(newValue) }
    }

    /// A record nobody answered says nothing at all.
    var isEmpty: Bool { emotions.isEmpty }

    /// "🌀 Тревожная · 🔥 Злая"
    var summaryLine: String {
        emotions.map { "\($0.emoji) \($0.label)" }.joined(separator: " · ")
    }

    private static func encode(_ emotions: [Emotion]) -> String {
        let unique = Set(emotions)
        return Emotion.allCases.filter(unique.contains).map(\.rawValue).joined(separator: "|")
    }
}
