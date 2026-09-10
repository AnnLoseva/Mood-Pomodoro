//
//  DiaryModels.swift
//  Mood Pomodoro
//

import Foundation

/// Aggregated day/month results for the Дневник screens. Same contract as
/// `AnalyticsModels`: views render these and never compute a statistic
/// themselves. Every figure here describes what was *observed* — nothing in
/// this file implies that one thing caused another.

/// Mood figures for an arbitrary set of check-ins (a day, a month, a group).
struct MoodStatistics {
    let average: Double?
    let distribution: MoodDistribution
    let checkInCount: Int
    /// Timestamp of the first 🥲/😭 in the period, if there was one.
    let firstDifficultMoodAt: Date?

    static let empty = MoodStatistics(
        average: nil,
        distribution: MoodDistribution(counts: [:], total: 0),
        checkInCount: 0,
        firstDifficultMoodAt: nil
    )

    var isEmpty: Bool { checkInCount == 0 }
}

/// One check-in placed on a day's clock — the intra-day mood chart's point.
struct TimeOfDayMoodPoint: Identifiable {
    let id: UUID
    let timestamp: Date
    let mood: Mood
    /// Distinguishes a session ping from a mood the user logged herself.
    let origin: CheckInOrigin
}

/// Time spent on one activity plus how it felt, for a day or a month.
struct ActivityDurationStatistics: Identifiable {
    var id: String { activityName }
    let activityName: String
    /// Work segments only — breaks excluded, matching `activeWorkDuration()`.
    let activeDuration: TimeInterval
    let breakDuration: TimeInterval
    let sessionCount: Int
    let checkInCount: Int
    let averageMood: Double?

    var hasEnoughData: Bool { checkInCount >= AnalyticsService.minimumSampleSize }
}

/// One cell of the month calendar.
struct DayMoodSummary: Identifiable {
    var id: Date { date }
    let date: Date
    let averageMood: Double?
    let checkInCount: Int

    /// The illustration/emoji to show for this day — nil when nothing was recorded.
    var representativeMood: Mood? { averageMood.map(Mood.nearest(to:)) }
}

/// One point of the "mood over the month" chart.
struct DateMoodPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let averageMood: Double
    let sampleCount: Int
}

/// Mood grouped by where the day fell in the cycle. Descriptive only — the
/// UI must never phrase these as a cause (see `AnalyticsService` header).
struct CycleMoodBucket: Identifiable {
    var id: String { label }
    let label: String
    let dayRange: ClosedRange<Int>
    let averageMood: Double?
    let checkInCount: Int

    var hasEnoughData: Bool { checkInCount >= AnalyticsService.minimumSampleSize }
}

/// Everything the day screen shows, computed once per selected date.
struct DailySummary {
    let date: Date
    let moodStats: MoodStatistics
    let moodPoints: [TimeOfDayMoodPoint]
    let timelineEvents: [TimelineEvent]
    let activities: [ActivityDurationStatistics]
    /// Distinct conditions recorded during the day's sessions.
    let conditions: [ConditionSnapshotEntry]
    let cycleDay: Int?
    let cycleEvents: [CycleEventKind]

    var totalActiveDuration: TimeInterval { activities.reduce(0) { $0 + $1.activeDuration } }
    var totalBreakDuration: TimeInterval { activities.reduce(0) { $0 + $1.breakDuration } }
    var sessionCount: Int { activities.reduce(0) { $0 + $1.sessionCount } }
    var isEmpty: Bool { moodStats.isEmpty && activities.isEmpty }
}

/// Everything the month screen shows.
struct MonthlySummary {
    /// First day of the month this covers.
    let month: Date
    let moodStats: MoodStatistics
    /// Every day of the month, in order — days with no data have a nil average.
    let days: [DayMoodSummary]
    let moodOverTime: [DateMoodPoint]
    let activities: [ActivityDurationStatistics]
    let factors: [FactorCategoryStatistics]
    let cycleBuckets: [CycleMoodBucket]

    var totalActiveDuration: TimeInterval { activities.reduce(0) { $0 + $1.activeDuration } }
    var sessionCount: Int { activities.reduce(0) { $0 + $1.sessionCount } }

    /// Days that stood out, best/hardest first. Only days that actually have
    /// check-ins are eligible — an empty day is not a "good" day.
    var bestDays: [DayMoodSummary] {
        days.filter { ($0.averageMood ?? 0) >= 4 }.sorted { ($0.averageMood ?? 0) > ($1.averageMood ?? 0) }
    }

    var difficultDays: [DayMoodSummary] {
        days.filter { day in day.averageMood.map { $0 <= 2.5 } ?? false }
            .sorted { ($0.averageMood ?? 5) < ($1.averageMood ?? 5) }
    }

    var isEmpty: Bool { moodStats.isEmpty && activities.isEmpty }
}

extension Mood {
    /// The mood whose 1–5 position is closest to an averaged value — used to
    /// pick one illustration for a day/period. Presentation only; the
    /// underlying average is never rounded in the data itself.
    static func nearest(to scale: Double) -> Mood {
        orderedCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .neutral
    }
}
