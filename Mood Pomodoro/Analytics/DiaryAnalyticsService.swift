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
///
/// And one rule underneath both: every record is placed by when the event
/// *happened* (`timestamp`, `startDate`, `day`), never by `createdAt`. An
/// entry written tonight about yesterday afternoon is yesterday afternoon.
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

    /// Whether `date` is a menstruation day by what was recorded: either the
    /// day itself carries a mark, or it lies between a start and the end
    /// recorded after it. A start with no end yet covers only the days the
    /// user actually marked — the app doesn't assume how long it lasted.
    static func isPeriodDay(_ date: Date, entries: [CycleEntry], calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if entries.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }) { return true }
        let sorted = entries.sorted { $0.date < $1.date }
        guard let lastStart = sorted.last(where: { $0.kind == .periodStart && $0.date <= day }) else { return false }
        return sorted.contains { entry in
            entry.kind == .periodEnd && entry.date > day && entry.date > lastStart.date
                && !sorted.contains { $0.kind == .periodStart && $0.date > lastStart.date && $0.date <= entry.date }
        }
    }

    // MARK: - Daily support

    /// The one mark for `day`. If sync left two (both devices marked the
    /// same day offline), the most recently edited wins.
    static func supportEntry(on day: Date, entries: [SupportEntry], calendar: Calendar = .current) -> SupportEntry? {
        entries
            .filter { $0.trackerKey == SupportEntry.defaultTrackerKey && calendar.isDate($0.day, inSameDayAs: day) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// Mood on the days of `interval` grouped by that day's support mark.
    /// Unmarked days are left out entirely — they are not "не принято".
    static func supportMoodStatistics(
        checkIns: [CheckIn],
        supportEntries: [SupportEntry],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [SupportMoodStat] {
        var statusByDay: [Date: SupportStatus] = [:]
        for entry in supportEntries where interval.contains(entry.day) {
            let day = calendar.startOfDay(for: entry.day)
            if let winner = supportEntry(on: day, entries: supportEntries, calendar: calendar) {
                statusByDay[day] = winner.status
            }
        }
        guard !statusByDay.isEmpty else { return [] }
        return SupportStatus.allCases.compactMap { status in
            let days = Set(statusByDay.filter { $0.value == status }.keys)
            guard !days.isEmpty else { return nil }
            let matching = checkIns.filter { days.contains(calendar.startOfDay(for: $0.timestamp)) }
            return SupportMoodStat(
                status: status,
                dayCount: days.count,
                checkInCount: matching.count,
                averageMood: averageMood(of: matching)
            )
        }
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
        supportEntries: [SupportEntry] = [],
        notes: [JournalNote] = [],
        diaryFactors: [ConditionEvent] = [],
        calendar: Calendar = .current
    ) -> DailySummary {
        let dayCheckIns = checkIns
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }
        let dayNotes = notes
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }
        let dayFactors = diaryFactors
            .filter { $0.session == nil && calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }
        let support = supportEntry(on: date, entries: supportEntries, calendar: calendar)

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
                session.timelineEvents.map { labelled($0, session: session) }
            }
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
        events.append(contentsOf: dayCheckIns.filter { $0.session == nil }.map(standaloneTimelineEvent))
        events.append(contentsOf: dayFactors.map(factorTimelineEvent))
        events.append(contentsOf: dayNotes.map(noteTimelineEvent))
        if let support, let time = support.time {
            events.append(
                TimelineEvent(
                    id: "support-\(support.id.uuidString)",
                    timestamp: time,
                    kind: .support,
                    title: L("Поддержка · \(support.status.label)", "Support · \(support.status.label)"),
                    subtitle: support.note,
                    mood: nil,
                    target: .support(support.day)
                )
            )
        }
        events.sort { $0.timestamp < $1.timestamp }

        var conditions = distinctConditions(in: startedToday)
        for entry in dayFactors.map(\.asSnapshotEntry) where !conditions.contains(where: { $0.optionID == entry.optionID }) {
            conditions.append(entry)
        }

        let kindOrder = CycleEventKind.allCases
        return DailySummary(
            date: calendar.startOfDay(for: date),
            moodStats: moodStatistics(of: dayCheckIns),
            moodPoints: dayCheckIns.map {
                TimeOfDayMoodPoint(id: $0.id, timestamp: $0.timestamp, mood: $0.mood, origin: $0.origin)
            },
            timelineEvents: events,
            activities: activityDurationStatistics(sessions: startedToday, checkIns: dayCheckIns),
            conditions: conditions,
            cycleDay: cycleDay(for: date, entries: cycleEntries, calendar: calendar),
            cycleEvents: cycleEntries
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .map(\.kind)
                .sorted { (kindOrder.firstIndex(of: $0) ?? 0) < (kindOrder.firstIndex(of: $1) ?? 0) },
            isPeriodDay: isPeriodDay(date, entries: cycleEntries, calendar: calendar),
            support: support.map { SupportDayStatus(status: $0.status, time: $0.time, note: $0.note) },
            notes: dayNotes.map { DiaryNoteEntry(id: $0.id, timestamp: $0.timestamp, text: $0.text) }
        )
    }

    // MARK: - Month

    static func monthlySummary(
        month: Date,
        sessions: [FocusSession],
        checkIns: [CheckIn],
        categories: [FactorCategory] = [],
        cycleEntries: [CycleEntry] = [],
        supportEntries: [SupportEntry] = [],
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
                cycleBuckets: [],
                supportStats: []
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
            cycleBuckets: cycleMoodBuckets(checkIns: monthCheckIns, entries: cycleEntries, calendar: calendar),
            supportStats: supportMoodStatistics(
                checkIns: monthCheckIns,
                supportEntries: supportEntries,
                in: interval,
                calendar: calendar
            )
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
                label: L("Дни \(range.lowerBound)–\(range.upperBound)", "Days \(range.lowerBound)–\(range.upperBound)"),
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
    ///
    /// Also attaches what each row edits: a backdated session's start/end
    /// open the activity form, and any check-in or condition opens its own.
    private static func labelled(_ event: TimelineEvent, session: FocusSession) -> TimelineEvent {
        let activity = Ldata(session.activity)
        var title = event.title
        var subtitle = event.subtitle
        var target: DiaryEditTarget?
        switch event.kind {
        case .start, .end:
            if !activity.isEmpty {
                title = event.kind == .start ? activity : L("\(activity) — завершение", "\(activity) — end")
            }
            if session.isManualEntry {
                target = .session(session.id)
                if event.kind == .start {
                    let range = DateFormatting.timeRange(from: session.startDate, to: session.endDate)
                    subtitle = [range, session.note].compactMap { $0 }.joined(separator: " · ")
                }
            }
        case .checkIn:
            target = uuid(in: event.id, after: "checkin-").map(DiaryEditTarget.checkIn)
        case .conditionChanged:
            target = uuid(in: event.id, after: "condition-").map(DiaryEditTarget.factor)
        default:
            break
        }
        return TimelineEvent(
            id: event.id,
            timestamp: event.timestamp,
            kind: event.kind,
            title: title,
            subtitle: subtitle,
            mood: event.mood,
            target: target
        )
    }

    private static func uuid(in id: String, after prefix: String) -> UUID? {
        guard id.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(prefix.count)))
    }

    private static func standaloneTimelineEvent(for checkIn: CheckIn) -> TimelineEvent {
        TimelineEvent(
            id: "standalone-\(checkIn.id.uuidString)",
            timestamp: checkIn.timestamp,
            kind: .checkIn,
            title: checkIn.reason.map(Ldata) ?? checkIn.mood.label,
            subtitle: checkIn.note,
            mood: checkIn.mood,
            target: .checkIn(checkIn.id)
        )
    }

    private static func factorTimelineEvent(for event: ConditionEvent) -> TimelineEvent {
        TimelineEvent(
            id: "diary-factor-\(event.id.uuidString)",
            timestamp: event.timestamp,
            kind: .conditionChanged,
            title: "\(event.categoryIcon) \(Ldata(event.optionName))",
            subtitle: Ldata(event.categoryName),
            mood: nil,
            target: .factor(event.id)
        )
    }

    private static func noteTimelineEvent(for note: JournalNote) -> TimelineEvent {
        TimelineEvent(
            id: "note-\(note.id.uuidString)",
            timestamp: note.timestamp,
            kind: .note,
            title: note.text,
            subtitle: nil,
            mood: nil,
            target: .note(note.id)
        )
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(24 * 60 * 60 - 1)
    }
}
