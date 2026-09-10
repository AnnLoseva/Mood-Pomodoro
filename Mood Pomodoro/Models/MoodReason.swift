//
//  MoodReason.swift
//  Mood Pomodoro
//
//  Data-driven check-in reasons, stored in SwiftData so they sync via
//  CloudKit instead of living only in this device's UserDefaults.
//

import Foundation
import SwiftData

@Model
final class MoodReason {
    var id: UUID = UUID()
    var moodRaw: String = Mood.neutral.rawValue
    var text: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), mood: Mood, text: String, sortOrder: Int) {
        self.id = id
        self.moodRaw = mood.rawValue
        self.text = text
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }
}
