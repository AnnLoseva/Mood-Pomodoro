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

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        mood: Mood,
        reason: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.moodRaw = mood.rawValue
        self.reason = reason
        self.note = note
    }

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }
}
