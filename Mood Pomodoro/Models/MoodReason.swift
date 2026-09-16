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
    /// Which scale this reason belongs to — a mood ("Грустно") or a
    /// motivation ("Застряла"). Defaults to `mood`, so every row written
    /// before motivation reasons existed keeps its meaning.
    var metricRaw: String = DayMetric.mood.rawValue
    /// The level's raw value on `metric`'s scale. Still named `moodRaw`
    /// because renaming a stored property would rename the CloudKit record
    /// field, which a synced store can't do after the fact — read it
    /// through `levelRaw` instead.
    var moodRaw: String = Mood.neutral.rawValue
    var text: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), metric: DayMetric, levelRaw: String, text: String, sortOrder: Int) {
        self.id = id
        self.metricRaw = metric.rawValue
        self.moodRaw = levelRaw
        self.text = text
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    convenience init(id: UUID = UUID(), mood: Mood, text: String, sortOrder: Int) {
        self.init(id: id, metric: .mood, levelRaw: mood.rawValue, text: text, sortOrder: sortOrder)
    }

    var metric: DayMetric {
        get { DayMetric(rawValue: metricRaw) ?? .mood }
        set { metricRaw = newValue.rawValue }
    }

    var levelRaw: String {
        get { moodRaw }
        set { moodRaw = newValue }
    }

    /// Nil on a row belonging to another scale.
    var mood: Mood? {
        guard metric == .mood else { return nil }
        return Mood(rawValue: moodRaw)
    }

    var motivation: StudyMotivation? {
        guard metric == .motivation else { return nil }
        return StudyMotivation(rawValue: moodRaw)
    }
}
