//
//  DiaryAnalyticsService.swift
//  Mood Pomodoro
//

import Foundation

/// Day- and month-scoped aggregation for the Дневник screens. Lives on
/// `AnalyticsService` so there is still exactly one place that turns raw
/// records into numbers, and stays pure (plain arrays in, value types out)
/// so the day/month math is testable without a `ModelContext`.
///
/// Two deliberate conventions, applied consistently everywhere below:
/// * A **check-in** belongs to the calendar day of its own `timestamp`. A
///   check-in answered at 00:15 counts toward the new day even if the
///   session began the evening before.
/// * A **session's time** is attributed to the day it *started* — the same
///   grouping `HistoryView` already uses, so a session and its study time
///   never appear split across two days.
extension AnalyticsService {

    // MARK: - Cycle

    /// Which day of the cycle `date` falls on, counting from the most recent
    /// recorded start (that day is day 1). Nil when nothing has been recorded
    /// on or before `date` — the app never guesses a start it wasn't told.
    static func cycleDay(for date: Date, entries: [CycleEntry], calendar: Calendar = .current) -> Int? {
        let day = calendar.startOfDay(for: date)
        let starts = entries
            .filter { $0.kind == .periodStart }
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()
        guard let lastStart = starts.last(where: { $0 <= day }) else { return nil }
        let elapsed = calendar.dateComponents([.day], from: lastStart, to: day).day ?? 0
        return elapsed + 1
    }

    // MARK: - Shared mood aggregation

    static func moodStatistics(of checkIns: [CheckIn]) -> MoodStatistics {
        MoodStatistics(
            average: averageMood(of: checkIns),
            distribution: moodDistribution(of: checkIns),
            checkInCount: checkIns.count,
            firstDifficultMoodAt: checkIns.filter { $0.mood.isDifficult }.map(\.timestamp).min()
        )
    }

    // MARK: - Day

    /// - Parameters:
    ///   - checkIns: *every* check-in, session-scoped and standalone alike —
    ///     this function does the day filtering. Passing only session
    ///     check-ins would silently drop manually logged moods.
    static func dailySummary(
        date: Date,
        sessions: [FocusSession],
        checkIns: [CheckIn],
        cycleEntries: [CycleEntry] = [],
        calendar: Calendar = .current
    ) -> DailySummary {
        let dayCheckIns = checkIns
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }

        // Time is attributed by start day; the timeline additionally shows
        // sessions that merely *overlap* the day, so a session running past
        // midnight still draws its events on both days.
        let startedToday = sessions.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
        let overlapping = sessions.filter { session in
            let end = session.endDate ?? Date.now
            return session.startDate <= endOfDay(date, calendar: calendar)
                && end >= calendar.startOfDay(for: date)
        }

        var events = overlapping
            .flatMap { session in
                session.timelineEvents.map { labelled($0, activity: session.activity) }
            }
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
        events.append(contentsOf: dayCheckIns.filter { $0.session == nil }.map(standaloneTimelineEvent))
        events.sort { $0.timestamp < $1.timestamp }

        return DailySummary(
            date: calendar.startOfDay(for: date),
            moodStats: moodStatistics(of: dayCheckIns),
            moodPoints: dayCheckIns.map {
                TimeOfDayMoodPoint(id: $0.id, timestamp: $0.timestamp, mood: $0.mood, origin: $0.origin)
            },
            timelineEvents: events,
            activities: activityDurationStatistics(sessions: startedToday, checkIns: dayCheckIns),
            conditions: distinctConditions(in: startedToday),
            cycleDay: cycleDay(for: date, entries: cycleEntries, calendar: calendar),
            cycleEvents: cycleEntries
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .map(\.kind)
        )
    }

    // MARK: - Month

    static func monthlySummary(
        month: Date,
        sessions: [FocusSession],
        checkIns: [CheckIn],
        categories: [FactorCategory] = [],
        cycleEntries: [CycleEntry] = [],
        calendar: Calendar = .current
    ) -> MonthlySummary {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return MonthlySummary(
                month: month,
                moodStats: .empty,
                days: [],
                moodOverTime: [],
                activities: [],
                factors: [],
                cycleBuckets: []
            )
        }

        let monthCheckIns = checkIns.filter { interval.contains($0.timestamp) }
        let monthSessions = sessions.filter { interval.contains($0.startDate) }

        let dayCount = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0
        let byDay = Dictionary(grouping: monthCheckIns) { calendar.startOfDay(for: $0.timestamp) }
        let days: [DayMoodSummary] = (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let dayStart = calendar.startOfDay(for: day)
            let entries = byDay[dayStart] ?? []
            return DayMoodSummary(
                date: dayStart,
                averageMood: averageMood(of: entries),
                checkInCount: entries.count
            )
        }

        return MonthlySummary(
            month: interval.start,
            moodStats: moodStatistics(of: monthCheckIns),
            days: days,
            moodOverTime: days.compactMap { day in
                guard let average = day.averageMood else { return nil }
                return DateMoodPoint(date: day.date, averageMood: average, sampleCount: day.checkInCount)
            },
            activities: activityDurationStatistics(sessions: monthSessions, checkIns: monthCheckIns),
            factors: categories.isEmpty ? [] : factorStatistics(categories: categories, sessions: monthSessions),
            cycleBuckets: cycleMoodBuckets(checkIns: monthCheckIns, entries: cycleEntries, calendar: calendar)
        )
    }

    /// Mood grouped into coarse stretches of the cycle. Ranges are fixed and
    /// descriptive — they are not phases, and a bucket below
    /// `minimumSampleSize` is reported with its count so the UI can say
    /// "недостаточно данных" instead of showing a confident-looking average.
    static func cycleMoodBuckets(
        checkIns: [CheckIn],
        entries: [CycleEntry],
        calendar: Calendar = .current
    ) -> [CycleMoodBucket] {
        guard !entries.isEmpty else { return [] }
        let ranges: [ClosedRange<Int>] = [1...5, 6...13, 14...18, 19...23, 24...45]
        var grouped: [Int: [CheckIn]] = [:]
        for checkIn in checkIns {
            guard let day = cycleDay(for: checkIn.timestamp, entries: entries, calendar: calendar),
                  let index = ranges.firstIndex(where: { $0.contains(day) }) else { continue }
            grouped[index, default: []].append(checkIn)
        }
        guard !grouped.isEmpty else { return [] }
        return ranges.enumerated().map { index, range in
            let matching = grouped[index] ?? []
            return CycleMoodBucket(
                label: "Дни \(range.lowerBound)–\(range.upperBound)",
                dayRange: range,
                averageMood: averageMood(of: matching),
                checkInCount: matching.count
            )
        }
    }

    // MARK: - Activities with time

    /// Per-activity time and mood. Durations come from `sessions`; mood comes
    /// from whichever of `checkIns` belong to those sessions, so a manually
    /// logged mood (no session) is counted in the day's overall figures but
    /// never attributed to an activity it was never tied to.
    static func activityDurationStatistics(
        sessions: [FocusSession],
        checkIns: [CheckIn]
    ) -> [ActivityDurationStatistics] {
        let grouped = Dictionary(grouping: sessions, by: \.activity)
        return grouped.map { activity, group in
            let ids = Set(group.map(\.id))
            let matching = checkIns.filter { checkIn in
                guard let sessionID = checkIn.session?.id else { return false }
                return ids.contains(sessionID)
            }
            return ActivityDurationStatistics(
                activityName: activity,
                activeDuration: group.reduce(0) { $0 + $1.activeWorkDuration() },
                breakDuration: group.reduce(0) { $0 + $1.breakDuration() },
                sessionCount: group.count,
                checkInCount: matching.count,
                averageMood: averageMood(of: matching)
            )
        }
        .sorted { $0.activeDuration > $1.activeDuration }
    }

    // MARK: - Helpers

    private static func distinctConditions(in sessions: [FocusSession]) -> [ConditionSnapshotEntry] {
        var seen: Set<ConditionSnapshotEntry> = []
        var ordered: [ConditionSnapshotEntry] = []
        for session in sessions {
            for event in session.sortedConditionEvents {
                let entry = event.asSnapshotEntry
                if seen.insert(entry).inserted { ordered.append(entry) }
            }
        }
        return ordered
    }

    /// A day can hold several sessions, so its start/end rows say *what*
    /// started rather than just "Начало" — that's what makes the day read as
    /// "математика, потом программирование". A single session's own screen
    /// already has the activity in its title, so this only applies here.
    private static func labelled(_ event: TimelineEvent, activity: String) -> TimelineEvent {
        guard event.kind == .start || event.kind == .end, !activity.isEmpty else { return event }
        return TimelineEvent(
            id: event.id,
            timestamp: event.timestamp,
            kind: event.kind,
            title: event.kind == .start ? activity : "\(activity) — завершение",
            subtitle: event.subtitle,
            mood: event.mood
        )
    }

    private static func standaloneTimelineEvent(for checkIn: CheckIn) -> TimelineEvent {
        TimelineEvent(
            id: "standalone-\(checkIn.id.uuidString)",
            timestamp: checkIn.timestamp,
            kind: .checkIn,
            title: checkIn.reason ?? checkIn.mood.label,
            subtitle: checkIn.note,
            mood: checkIn.mood
        )
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(24 * 60 * 60 - 1)
    }
}
