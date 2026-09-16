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

/// One check-in placed on a day's clock — a point of the intra-day chart.
/// Carries all three scales, since they are recorded together; `energy` and
/// `motivation` are nil on a check-in where only a mood was noted, and
/// those points are simply absent from their series rather than guessed at.
struct TimeOfDayMoodPoint: Identifiable {
    let id: UUID
    let timestamp: Date
    let mood: Mood
    let energy: EnergyLevel?
    let motivation: StudyMotivation?
    /// Distinguishes a session ping from a mood the user logged herself.
    let origin: CheckInOrigin

    /// This point's value for one series, or nil when it wasn't recorded.
    func scale(for metric: DayMetric) -> Double? {
        switch metric {
        case .mood: return mood.scale
        case .energy: return energy?.scale
        case .motivation: return motivation?.scale
        }
    }
}

/// One session drawn behind the day's mood chart: when it ran and what it
/// was. Clipped to the day; breaks are the gaps between `workIntervals`.
struct ActivitySpan: Identifiable {
    let id: UUID
    let activityName: String
    let start: Date
    let end: Date
    let workIntervals: [DateInterval]
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
    var hasMoodData: Bool { averageMood != nil }
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

/// The day's support mark, as the user recorded it. Nil on `DailySummary`
/// means "не отмечено" — a different answer from `.notTaken`.
struct SupportDayStatus {
    let status: SupportStatus
    /// Nil = "в течение дня"; the user is never made to pick a time.
    let time: Date?
    let note: String?
}

/// Mood on days carrying one support mark, for the month. Observational
/// only: "в дни с отметкой «принято» среднее было X" — never a claim that
/// one caused the other.
struct SupportMoodStat: Identifiable {
    var id: String { status.rawValue }
    let status: SupportStatus
    let dayCount: Int
    let checkInCount: Int
    let averageMood: Double?

    var hasEnoughData: Bool { checkInCount >= AnalyticsService.minimumSampleSize }
}

/// A free-text diary note placed on its day.
struct DiaryNoteEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
}

/// Everything the day screen shows, computed once per selected date.
struct DailySummary {
    let date: Date
    let moodStats: MoodStatistics
    let moodPoints: [TimeOfDayMoodPoint]
    /// Every session that overlapped the day, oldest first.
    let activitySpans: [ActivitySpan]
    let timelineEvents: [TimelineEvent]
    let activities: [ActivityDurationStatistics]
    /// Distinct conditions recorded that day — during sessions or added to
    /// the diary on their own.
    let conditions: [ConditionSnapshotEntry]
    let cycleDay: Int?
    let cycleEvents: [CycleEventKind]
    /// True when the day was marked as, or falls between a recorded start
    /// and end of, menstruation. Never inferred past what was recorded.
    let isPeriodDay: Bool
    let support: SupportDayStatus?
    let notes: [DiaryNoteEntry]

    var totalActiveDuration: TimeInterval { activities.reduce(0) { $0 + $1.activeDuration } }
    var totalBreakDuration: TimeInterval { activities.reduce(0) { $0 + $1.breakDuration } }
    var sessionCount: Int { activities.reduce(0) { $0 + $1.sessionCount } }

    /// The day's points for one series, oldest first. A metric nobody
    /// recorded today comes back empty — which is how the day chart knows
    /// to offer its toggle as unavailable rather than as an empty line.
    func points(for metric: DayMetric) -> [TimeOfDayMoodPoint] {
        moodPoints.filter { $0.scale(for: metric) != nil }
    }

    /// Mean of what was recorded for one series, nil when nothing was.
    func average(for metric: DayMetric) -> Double? {
        let values = moodPoints.compactMap { $0.scale(for: metric) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The series that have anything to draw today, in legend order.
    var recordedMetrics: [DayMetric] {
        DayMetric.allCases.filter { !points(for: $0).isEmpty }
    }
    var isEmpty: Bool {
        moodStats.isEmpty && activities.isEmpty && conditions.isEmpty && notes.isEmpty && support == nil
    }
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
    let supportStats: [SupportMoodStat]

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
