//
//  DayContextModels.swift
//  Mood Pomodoro
//

import Foundation
import SwiftUI

/// One day, reduced to a single row of answers — the shape every
/// day-to-day comparison in the app runs on.
///
/// Why this exists at all: a comparison over *check-ins* lets a day with
/// twenty entries outweigh a day with one, which turns "чаще отмечаюсь,
/// когда плохо" into a fake pattern. So each day is collapsed to one value
/// per scale first, and the comparison is then over days. Both counts are
/// kept — how many days, and how many observations went into them — so the
/// UI can always say what a figure rests on.
///
/// Nil is nil throughout: a scale nobody recorded that day is absent, never
/// a zero and never a middling three.
struct DayAggregate: Identifiable {
    var id: Date { day }
    let day: Date

    /// Mean of the day's own check-ins, unweighted — one day, one number.
    let mood: Double?
    let moodCount: Int
    let energy: Double?
    let energyCount: Int
    let motivation: Double?
    let motivationCount: Int
    let hunger: Double?
    let hungerCount: Int
    let appetite: Double?
    let appetiteCount: Int

    /// Night sleep filed under this day (the day she woke up), with naps
    /// kept apart. Nil means no record — never "не спала".
    let sleepDuration: TimeInterval?
    let napDuration: TimeInterval
    let sleepQuality: SleepQuality?

    let cycleDay: Int?
    let isPeriodDay: Bool
    /// Nil is "не отмечено", which is a different answer from `.notTaken`.
    let support: SupportStatus?

    let mealCount: Int
    let treatCount: Int

    /// Which feelings appeared that day, each counted once however many
    /// times it was recorded.
    let emotions: Set<Emotion>
    let impulseCount: Int
    let impulsesByCategory: [ImpulseCategory: Int]

    /// Active work time per session type; `nil` key holds the untyped
    /// sessions. Breaks are excluded, as everywhere else.
    let durationByType: [SessionType?: TimeInterval]
    let sessionCount: Int
    var sessionCountsByType: [SessionType?: Int] = [:]

    var totalActiveDuration: TimeInterval { durationByType.values.reduce(0, +) }

    func duration(of type: SessionType?) -> TimeInterval { durationByType[type] ?? 0 }

    /// The value of one 1–5 scale for this day, or nil if it wasn't recorded.
    func value(for metric: DayScaleMetric) -> Double? {
        switch metric {
        case .mood: return mood
        case .energy: return energy
        case .motivation: return motivation
        case .hunger: return hunger
        case .appetite: return appetite
        }
    }

    func observationCount(for metric: DayScaleMetric) -> Int {
        switch metric {
        case .mood: return moodCount
        case .energy: return energyCount
        case .motivation: return motivation == nil ? 0 : motivationCount
        case .hunger: return hungerCount
        case .appetite: return appetiteCount
        }
    }

    /// True when the day holds nothing at all — used to keep empty days out
    /// of comparisons without pretending they were zeros.
    var isEmpty: Bool {
        moodCount == 0 && energyCount == 0 && motivationCount == 0 && hungerCount == 0
            && appetiteCount == 0 && sleepDuration == nil && napDuration == 0 && support == nil
            && !isPeriodDay && mealCount == 0 && emotions.isEmpty && impulseCount == 0
            && durationByType.isEmpty
    }
}

/// The five 1–5 scales a day can be described by. Mood, energy and
/// motivation are the check-in's own; hunger and appetite come from their
/// own records and are never merged with each other.
enum DayScaleMetric: String, CaseIterable, Identifiable, Sendable {
    case mood
    case energy
    case motivation
    case hunger
    case appetite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mood: return L("настроение", "mood")
        case .energy: return L("силы", "energy")
        case .motivation: return L("мотивация", "motivation")
        case .hunger: return L("голод", "hunger")
        case .appetite: return L("аппетит", "appetite")
        }
    }

    var title: String {
        switch self {
        case .mood: return L("Настроение", "Mood")
        case .energy: return L("Энергия", "Energy")
        case .motivation: return L("Мотивация", "Motivation")
        case .hunger: return L("Голод", "Hunger")
        case .appetite: return L("Аппетит", "Appetite")
        }
    }

    /// Colours for the unified chart. Mood/energy/motivation match the day
    /// chart; hunger and appetite sit apart from those three and from each
    /// other, so five lines on one 1–5 axis stay tellable apart.
    var color: Color {
        switch self {
        case .mood: return DayMetric.mood.color
        case .energy: return DayMetric.energy.color
        case .motivation: return DayMetric.motivation.color
        case .hunger: return Color(red: 0.243, green: 0.537, blue: 0.518)
        case .appetite: return Color(red: 0.769, green: 0.412, blue: 0.275)
        }
    }
}

/// One scale inside one group of days: the average *of daily averages*, how
/// many days it rests on, and how many individual entries those days held.
struct DayScaleFigure: Identifiable {
    var id: String { metric.rawValue }
    let metric: DayScaleMetric
    let average: Double?
    /// Days that had any record of this scale — the sample size that counts.
    let dayCount: Int
    /// Individual entries behind those days, shown so "5 дней (37 отметок)"
    /// can be stated plainly.
    let observationCount: Int

    var hasEnoughData: Bool { dayCount >= AnalyticsService.minimumSampleSize }
}

/// A named set of days put side by side with others — "ночи короче 6 часов",
/// "дни с отметкой «принято»", "дни менструации".
///
/// Every figure is an average over days, and every one carries its own
/// sample size. Nothing here is a cause: the UI must phrase these as
/// co-occurrences, which is all they are.
struct DayContextGroup: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    /// Days in the group, whether or not they recorded any given scale.
    let dayCount: Int
    let scales: [DayScaleFigure]

    /// Average night length over the days in the group that had one.
    let averageSleep: TimeInterval?
    let sleepDayCount: Int
    var sessionCountsByType: [SessionType?: Int] = [:]

    let mealCount: Int
    let treatCount: Int
    let impulseCount: Int
    /// Days that carried at least one impulse record.
    let impulseDayCount: Int
    /// Active time per session type, summed over the group's days.
    let durationByType: [SessionType?: TimeInterval]
    /// Feelings recorded on these days, most frequent first.
    let emotions: [EmotionCount]

    var hasEnoughData: Bool { dayCount >= AnalyticsService.minimumSampleSize }

    func figure(for metric: DayScaleMetric) -> DayScaleFigure? {
        scales.first { $0.metric == metric }
    }

    var totalActiveDuration: TimeInterval { durationByType.values.reduce(0, +) }
}

/// The day as the diary's «Состояние дня» block shows it. Built once, from
/// the same aggregation the calendar and the charts read, so the card can
/// never drift from the month behind it.
struct DayState {
    let date: Date
    /// Average of the day's recorded moods, or nil for "нет данных" — which
    /// is shown as its own state and never as a neutral mood.
    let averageMood: Double?
    let moodCount: Int
    /// Night sleep for this day. Nil means nothing was recorded.
    let sleepDuration: TimeInterval?
    let napDuration: TimeInterval
    let sleepQuality: SleepQuality?
    let cycleDay: Int?
    let isPeriodDay: Bool
    let support: SupportDayStatus?
    let emotions: [Emotion]
    let activeDuration: TimeInterval
    let durationByType: [SessionType?: TimeInterval]
    let mealCount: Int
    let impulseCount: Int

    var hasMood: Bool { averageMood != nil }
    var hasSleep: Bool { sleepDuration != nil || napDuration > 0 }
}
