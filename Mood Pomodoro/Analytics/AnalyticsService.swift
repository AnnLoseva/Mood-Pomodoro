//
//  AnalyticsService.swift
//  Mood Pomodoro
//

import Foundation

/// Turns raw `FocusSession`/`CheckIn` data into the aggregated statistics
/// Views render. Pure functions over plain arrays — no `ModelContext`, no
/// SwiftUI — so a view never computes a statistic itself and this stays
/// trivially testable.
///
/// This app doesn't run experiments: every function here describes what was
/// *observed*, never what *caused* what. Keep phrasing in the UI layer
/// neutral ("associated with", "in your observations") — this service only
/// hands back numbers, not sentences that could imply causation.
enum AnalyticsService {
    /// Below this many check-ins, a group's numbers are shown but never
    /// used to make a comparative claim ("insufficient data" instead).
    static let minimumSampleSize = 5

    // MARK: - Overview

    /// - Parameter standaloneCheckIns: moods logged outside any session. They
    ///   count toward the mood figures — the user answered them the same way —
    ///   but not toward session counts or durations, which they have none of.
    static func overview(
        sessions: [FocusSession],
        standaloneCheckIns: [CheckIn] = []
    ) -> OverviewStatistics {
        let checkIns = sessions.flatMap { $0.checkIns ?? [] } + standaloneCheckIns
        let finished = sessions.filter { $0.state == .completed }
        return OverviewStatistics(
            averageMood: averageMood(of: checkIns),
            checkInCount: checkIns.count,
            sessionCount: finished.count,
            averageSessionDuration: averageDuration(of: finished),
            averageTimeToFirstDifficultMood: averageTimeToFirstDifficultMood(sessions: sessions),
            moodDistribution: moodDistribution(of: checkIns)
        )
    }

    static func averageMood(of checkIns: [CheckIn]) -> Double? {
        guard !checkIns.isEmpty else { return nil }
        return checkIns.reduce(0.0) { $0 + $1.mood.scale } / Double(checkIns.count)
    }

    static func moodDistribution(of checkIns: [CheckIn]) -> MoodDistribution {
        var counts: [Mood: Int] = [:]
        for mood in Mood.allCases { counts[mood] = 0 }
        for checkIn in checkIns { counts[checkIn.mood, default: 0] += 1 }
        return MoodDistribution(counts: counts, total: checkIns.count)
    }

    static func averageDuration(of sessions: [FocusSession]) -> TimeInterval? {
        let durations = sessions.compactMap { session -> TimeInterval? in
            guard session.endDate != nil else { return nil }
            return session.activeWorkDuration()
        }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    static func averageTimeToFirstDifficultMood(sessions: [FocusSession]) -> TimeInterval? {
        let times = sessions.compactMap { session -> TimeInterval? in
            guard let first = session.sortedCheckIns.first(where: { $0.mood.isDifficult }) else { return nil }
            // Breaks are not active work — "time to fatigue" is elapsed
            // *work* at the check-in, not wall-clock since session start.
            return session.elapsedActiveTime(asOf: first.timestamp)
        }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    // MARK: - Mood over time (trajectory / time-based analytics)

    /// Average mood bucketed by elapsed minutes since each session's start —
    /// this is both the "mood trajectory" chart and the section 17
    /// time-based table; they're the same computation at different
    /// presentation.
    static func moodTrajectory(sessions: [FocusSession], bucketMinutes: Int = 20) -> [MoodTimelinePoint] {
        var buckets: [Int: [Double]] = [:]
        for session in sessions {
            for checkIn in session.checkIns ?? [] {
                let elapsedMinutes = checkIn.timestamp.timeIntervalSince(session.startDate) / 60
                guard elapsedMinutes >= 0 else { continue }
                let bucketStart = (Int(elapsedMinutes) / bucketMinutes) * bucketMinutes
                buckets[bucketStart, default: []].append(checkIn.mood.scale)
            }
        }
        return buckets.keys.sorted().map { start in
            let values = buckets[start] ?? []
            return MoodTimelinePoint(
                minuteBucketStart: start,
                averageMood: values.reduce(0, +) / Double(values.count),
                sampleCount: values.count
            )
        }
    }

    /// A single session's own check-ins as (elapsed minutes, mood) points — no
    /// bucketing, just that session's raw trajectory for its detail screen.
    static func sessionTrajectory(_ session: FocusSession) -> [(minutes: Double, mood: Mood)] {
        session.sortedCheckIns.map { ($0.timestamp.timeIntervalSince(session.startDate) / 60, $0.mood) }
    }

    /// A short, neutral observation about where mood tends to dip, or nil if
    /// there isn't a clear enough pattern yet to say anything.
    static func declineObservation(trajectory: [MoodTimelinePoint]) -> String? {
        guard trajectory.count >= 2 else { return nil }
        var runningBest = trajectory[0].averageMood
        for point in trajectory {
            runningBest = max(runningBest, point.averageMood)
            if runningBest - point.averageMood >= 0.7, point.sampleCount >= minimumSampleSize {
                return L("В твоих сессиях состояние обычно начинает снижаться примерно после \(point.minuteBucketStart) минут.", "In your sessions, mood usually starts to dip after about \(point.minuteBucketStart) minutes.")
            }
        }
        return nil
    }

    // MARK: - Factors

    static func factorStatistics(
        categories: [FactorCategory],
        sessions: [FocusSession],
        activity: String? = nil
    ) -> [FactorCategoryStatistics] {
        let checkIns = filteredCheckIns(sessions: sessions, activity: activity)
        return categories.filter(\.isEnabled).map { category in
            let optionStats = category.enabledOptions.map {
                optionStatistics(category: category, option: $0, checkIns: checkIns)
            }
            return FactorCategoryStatistics(
                id: category.id,
                categoryName: category.name,
                categoryIcon: category.icon,
                optionStats: optionStats
            )
        }
    }

    static func optionStatistics(
        category: FactorCategory,
        option: FactorOption,
        checkIns: [CheckIn]
    ) -> FactorOptionStatistics {
        let matching = checkIns.filter { $0.hasCondition(categoryID: category.id, optionID: option.id) }
        return FactorOptionStatistics(
            id: option.id,
            optionName: option.name,
            optionIcon: option.icon,
            optionIconImageName: option.iconImageName ?? category.iconImageName,
            averageMood: averageMood(of: matching),
            checkInCount: matching.count,
            goodMoodShare: goodMoodShare(of: matching),
            averageMinutesToDifficult: averageMinutesToDifficult(of: matching)
        )
    }

    static func goodMoodShare(of checkIns: [CheckIn]) -> Double? {
        guard !checkIns.isEmpty else { return nil }
        let good = checkIns.filter { $0.mood == .veryGood || $0.mood == .good }.count
        return Double(good) / Double(checkIns.count)
    }

    /// Average elapsed minutes (from session start) to the first difficult
    /// check-in *among the ones matching this filter*, one figure per
    /// session that has such a check-in.
    static func averageMinutesToDifficult(of checkIns: [CheckIn]) -> Double? {
        let bySession = Dictionary(grouping: checkIns.filter { $0.session != nil }) { $0.session!.id }
        var minutes: [Double] = []
        for group in bySession.values {
            guard let session = group.first?.session else { continue }
            guard let firstDifficult = group.filter({ $0.mood.isDifficult }).min(by: { $0.timestamp < $1.timestamp }) else { continue }
            minutes.append(firstDifficult.timestamp.timeIntervalSince(session.startDate) / 60)
        }
        guard !minutes.isEmpty else { return nil }
        return minutes.reduce(0, +) / Double(minutes.count)
    }

    static func filteredCheckIns(sessions: [FocusSession], activity: String?) -> [CheckIn] {
        let relevant: [FocusSession]
        if let activity {
            relevant = sessions.filter { $0.activity == activity }
        } else {
            relevant = sessions
        }
        return relevant.flatMap { $0.checkIns ?? [] }
    }

    // MARK: - Activities

    static func activityStatistics(sessions: [FocusSession]) -> [ActivityStatistics] {
        var grouped: [String: [CheckIn]] = [:]
        for session in sessions {
            grouped[session.activity, default: []].append(contentsOf: session.checkIns ?? [])
        }
        return grouped
            .map { ActivityStatistics(activityName: $0.key, averageMood: averageMood(of: $0.value), checkInCount: $0.value.count) }
            .sorted { ($0.averageMood ?? 0) > ($1.averageMood ?? 0) }
    }

    // MARK: - Reasons

    static func reasonStatistics(
        mood: Mood,
        sessions: [FocusSession],
        standaloneCheckIns: [CheckIn] = []
    ) -> [ReasonStatistic] {
        let all = sessions.flatMap { $0.checkIns ?? [] } + standaloneCheckIns
        let reasons = all.filter { $0.mood == mood }.compactMap(\.reason)
        guard !reasons.isEmpty else { return [] }
        let counts = Dictionary(grouping: reasons, by: { $0 }).mapValues(\.count)
        let total = reasons.count
        return counts
            .map { ReasonStatistic(reason: $0.key, count: $0.value, percentage: Double($0.value) / Double(total)) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Comparison & combinations

    static func compare(
        optionA: (category: FactorCategory, option: FactorOption),
        optionB: (category: FactorCategory, option: FactorOption),
        sessions: [FocusSession],
        activity: String? = nil
    ) -> ComparisonResult {
        let checkIns = filteredCheckIns(sessions: sessions, activity: activity)
        return ComparisonResult(
            optionA: optionStatistics(category: optionA.category, option: optionA.option, checkIns: checkIns),
            optionB: optionStatistics(category: optionB.category, option: optionB.option, checkIns: checkIns)
        )
    }

    /// Stats for check-ins where *every* selected (category, option) pair was
    /// simultaneously active — a manually-built combination, never an
    /// automatic cross-product of all factors (section 15).
    static func combinationStatistics(
        selections: [(category: FactorCategory, option: FactorOption)],
        sessions: [FocusSession]
    ) -> FactorOptionStatistics {
        let checkIns = sessions.flatMap { $0.checkIns ?? [] }.filter { checkIn in
            selections.allSatisfy { checkIn.hasCondition(categoryID: $0.category.id, optionID: $0.option.id) }
        }
        let name = selections.map { Ldata($0.option.name) }.joined(separator: " + ")
        let icon = selections.first?.category.icon ?? "🍄"
        return FactorOptionStatistics(
            id: UUID(),
            optionName: name,
            optionIcon: icon,
            optionIconImageName: nil,
            averageMood: averageMood(of: checkIns),
            checkInCount: checkIns.count,
            goodMoodShare: goodMoodShare(of: checkIns),
            averageMinutesToDifficult: averageMinutesToDifficult(of: checkIns)
        )
    }

    // MARK: - Overview insight widget

    /// Top factor values whose average mood, with enough data, sits highest
    /// above the overall average — the "what's linked to a good mood" list.
    static func topPositiveFactors(categories: [FactorCategory], sessions: [FocusSession], limit: Int = 3) -> [FactorInsight] {
        let allCheckIns = sessions.flatMap { $0.checkIns ?? [] }
        guard let overallAverage = averageMood(of: allCheckIns) else { return [] }

        var insights: [FactorInsight] = []
        for category in categories.filter(\.isEnabled) {
            for option in category.enabledOptions {
                let matching = allCheckIns.filter { $0.hasCondition(categoryID: category.id, optionID: option.id) }
                guard matching.count >= minimumSampleSize, let avg = averageMood(of: matching) else { continue }
                insights.append(FactorInsight(
                    id: option.id,
                    icon: category.icon,
                    iconImageName: option.iconImageName ?? category.iconImageName,
                    name: option.name,
                    moodDelta: avg - overallAverage
                ))
            }
        }
        return insights.sorted { $0.moodDelta > $1.moodDelta }.prefix(limit).map { $0 }
    }
}

private extension CheckIn {
    func hasCondition(categoryID: UUID, optionID: UUID) -> Bool {
        conditionSnapshot.contains { $0.categoryID == categoryID && $0.optionID == optionID }
    }
}
