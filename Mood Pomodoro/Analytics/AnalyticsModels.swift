//
//  AnalyticsModels.swift
//  Mood Pomodoro
//

import Foundation

/// Aggregated results `AnalyticsService` hands to the UI. Views only ever
/// render these — they never touch `CheckIn`/`FocusSession` arrays or
/// compute a statistic themselves.

struct MoodDistribution {
    var counts: [Mood: Int]
    var total: Int

    func percentage(for mood: Mood) -> Double? {
        guard total > 0 else { return nil }
        return Double(counts[mood] ?? 0) / Double(total)
    }
}

struct MoodTimelinePoint: Identifiable {
    var id: Int { minuteBucketStart }
    let minuteBucketStart: Int
    let averageMood: Double
    let sampleCount: Int
}

struct OverviewStatistics {
    let averageMood: Double?
    let checkInCount: Int
    let sessionCount: Int
    let averageSessionDuration: TimeInterval?
    let averageTimeToFirstDifficultMood: TimeInterval?
    let moodDistribution: MoodDistribution
}

/// Stats for one value of one factor (e.g. "Lo-fi" under "Музыка"), or for a
/// manually-built combination of several conditions at once.
struct FactorOptionStatistics: Identifiable {
    let id: UUID
    let optionName: String
    let optionIcon: String
    let optionIconImageName: String?
    let averageMood: Double?
    let checkInCount: Int
    /// Share of check-ins that were 😍/😄.
    let goodMoodShare: Double?
    let averageMinutesToDifficult: Double?

    var hasEnoughData: Bool { checkInCount >= AnalyticsService.minimumSampleSize }
}

struct FactorCategoryStatistics: Identifiable {
    let id: UUID
    let categoryName: String
    let categoryIcon: String
    let optionStats: [FactorOptionStatistics]
}

struct ActivityStatistics: Identifiable {
    var id: String { activityName }
    let activityName: String
    let averageMood: Double?
    let checkInCount: Int

    var hasEnoughData: Bool { checkInCount >= AnalyticsService.minimumSampleSize }
}

struct ReasonStatistic: Identifiable {
    var id: String { reason }
    let reason: String
    let count: Int
    let percentage: Double
}

struct ComparisonResult {
    let optionA: FactorOptionStatistics
    let optionB: FactorOptionStatistics

    var canCompare: Bool { optionA.hasEnoughData && optionB.hasEnoughData }

    var moodDifference: Double? {
        guard let a = optionA.averageMood, let b = optionB.averageMood else { return nil }
        return a - b
    }
}

/// One entry in the "what's linked to a good mood" overview widget.
struct FactorInsight: Identifiable {
    var id: UUID
    let icon: String
    let iconImageName: String?
    let name: String
    let moodDelta: Double
}
