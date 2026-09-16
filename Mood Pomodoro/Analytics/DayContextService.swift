//
//  DayContextService.swift
//  Mood Pomodoro
//

import Foundation

/// Day-level aggregation: everything the app knows about a day reduced to
/// one row, and days then compared with days.
///
/// The rule this file exists for: **aggregate inside the day first.** A day
/// with twenty check-ins and a day with one must weigh the same when the
/// question is "как выглядели дни после коротких ночей" — otherwise the
/// answer is mostly a measurement of how often she opened the app.
///
/// Everything here is descriptive. Groups are put side by side, sample
/// sizes travel with every figure, and nothing in this file decides that
/// one thing caused another.
///
/// Sleep arrives as plain `SleepSessionSummary` values, like in
/// `SleepAnalyticsService` — it lives in the local-only health store and
/// never becomes part of a synced model.
extension AnalyticsService {

    /// One row per day that has anything on it.
    ///
    /// - Parameters:
    ///   - checkIns: every check-in, session-scoped and standalone alike.
    ///   - sleepSessions: already overlap-resolved (see
    ///     `SleepAggregationService.resolveOverlaps(sessions:)`); superseded
    ///     records are skipped here too, so a night can never count twice.
    static func dayAggregates(
        in interval: DateInterval? = nil,
        checkIns: [CheckIn] = [],
        sessions: [FocusSession] = [],
        hungerEntries: [HungerEntry] = [],
        foodEntries: [FoodEntry] = [],
        emotionEntries: [EmotionEntry] = [],
        impulseEntries: [ImpulseEntry] = [],
        supportEntries: [SupportEntry] = [],
        cycleMarks: [CycleMark] = [],
        healthMedication: [Date: HealthMedicationDay] = [:],
        sleepSessions: [SleepSessionSummary] = [],
        calendar: Calendar = .current
    ) -> [DayAggregate] {
        func inRange(_ date: Date) -> Bool {
            guard let interval else { return true }
            return date >= interval.start && date < interval.end
        }
        func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

        var days = Set<Date>()
        let checkInsByDay = Dictionary(grouping: checkIns.filter { inRange($0.timestamp) }) { day($0.timestamp) }
        let hungerByDay = Dictionary(grouping: hungerEntries.filter { !$0.isEmpty && inRange($0.eventDate) }) { day($0.eventDate) }
        let foodByDay = Dictionary(grouping: foodEntries.filter { inRange($0.eventDate) }) { day($0.eventDate) }
        let emotionsByDay = Dictionary(grouping: emotionEntries.filter { !$0.isEmpty && inRange($0.eventDate) }) { day($0.eventDate) }
        let impulsesByDay = Dictionary(grouping: impulseEntries.filter { inRange($0.eventDate) }) { day($0.eventDate) }
        // A session's time belongs to the day it started, the same rule the
        // diary and the history already use.
        let sessionsByDay = Dictionary(grouping: sessions.filter { inRange($0.startDate) }) { day($0.startDate) }
        let sleepByDay = Dictionary(grouping: SleepAggregationService.resolveOverlaps(sessions: sleepSessions).filter { !$0.isSuperseded && inRange($0.day) }) { day($0.day) }
        let supportByDay = Dictionary(
            grouping: supportEntries.filter { $0.trackerKey == SupportEntry.defaultTrackerKey && inRange($0.day) }
        ) { day($0.day) }

        days.formUnion(checkInsByDay.keys)
        days.formUnion(hungerByDay.keys)
        days.formUnion(foodByDay.keys)
        days.formUnion(emotionsByDay.keys)
        days.formUnion(impulsesByDay.keys)
        days.formUnion(sessionsByDay.keys)
        days.formUnion(sleepByDay.keys)
        days.formUnion(supportByDay.keys)
        days.formUnion(healthMedication.keys.filter(inRange).map(day))
        days.formUnion(cycleMarks.map { day($0.day) }.filter(inRange))

        return days.sorted().map { date in
            let dayCheckIns = checkInsByDay[date] ?? []
            let dayHunger = hungerByDay[date] ?? []
            let dayFood = foodByDay[date] ?? []
            let dayEmotions = emotionsByDay[date] ?? []
            let dayImpulses = impulsesByDay[date] ?? []
            let daySessions = sessionsByDay[date] ?? []
            let daySleep = sleepByDay[date] ?? []

            let energies = dayCheckIns.compactMap(\.energy)
            let motivations = dayCheckIns.compactMap(\.motivation)
            let hungers = dayHunger.compactMap(\.hunger)
            let appetites = dayHunger.compactMap(\.appetite)

            let nights = daySleep.filter { $0.kind == .night }
            let naps = daySleep.filter { $0.kind == .nap }

            // Her own mark wins; Health only answers for days she didn't mark.
            let support = supportEntry(on: date, entries: supportByDay[date] ?? [], calendar: calendar)?.status
                ?? healthMedication[date].flatMap { $0.status }

            var durationByType: [SessionType?: TimeInterval] = [:]
            for session in daySessions {
                durationByType[session.sessionType, default: 0] += session.activeWorkDuration()
            }

            var impulsesByCategory: [ImpulseCategory: Int] = [:]
            for impulse in dayImpulses { impulsesByCategory[impulse.category, default: 0] += 1 }

            return DayAggregate(
                day: date,
                mood: timeWeightedAverageMood(of: dayCheckIns),
                moodCount: dayCheckIns.count,
                energy: averageScale(energies),
                energyCount: energies.count,
                motivation: averageScale(motivations),
                motivationCount: motivations.count,
                hunger: averageScale(hungers),
                hungerCount: hungers.count,
                appetite: averageScale(appetites),
                appetiteCount: appetites.count,
                sleepDuration: nights.isEmpty ? nil : nights.reduce(0) { $0 + $1.totalSleep },
                napDuration: naps.reduce(0) { $0 + $1.totalSleep },
                sleepQuality: nights.compactMap(\.quality).first ?? daySleep.compactMap(\.quality).first,
                cycleDay: cycleDay(for: date, marks: cycleMarks, calendar: calendar),
                isPeriodDay: isPeriodDay(date, marks: cycleMarks, calendar: calendar),
                support: support,
                mealCount: dayFood.count,
                treatCount: dayFood.filter { $0.category == .treat }.count,
                emotions: Set(dayEmotions.flatMap(\.emotions)),
                impulseCount: dayImpulses.count,
                impulsesByCategory: impulsesByCategory,
                durationByType: durationByType,
                sessionCount: daySessions.count,
                sessionCountsByType: Dictionary(grouping: daySessions) { $0.sessionType }.mapValues(\.count)
            )
        }
    }

    // MARK: - Grouping days

    /// Describes one set of days. Every scale is the mean of that set's
    /// *daily* values, so one talkative day can't outvote a quiet one.
    static func describe(days: [DayAggregate], key: String, label: String) -> DayContextGroup {
        let scales = DayScaleMetric.allCases.map { metric -> DayScaleFigure in
            let values = days.compactMap { $0.value(for: metric) }
            return DayScaleFigure(
                metric: metric,
                average: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                dayCount: values.count,
                observationCount: days.reduce(0) { $0 + $1.observationCount(for: metric) }
            )
        }
        let nights = days.compactMap(\.sleepDuration)
        var durationByType: [SessionType?: TimeInterval] = [:]
        for day in days {
            for (type, duration) in day.durationByType {
                durationByType[type, default: 0] += duration
            }
        }
        var emotionCounts: [Emotion: Int] = [:]
        for day in days {
            for emotion in day.emotions { emotionCounts[emotion, default: 0] += 1 }
        }

        return DayContextGroup(
            key: key,
            label: label,
            dayCount: days.count,
            scales: scales,
            averageSleep: nights.isEmpty ? nil : nights.reduce(0, +) / Double(nights.count),
            sleepDayCount: nights.count,
            sessionCountsByType: days.reduce(into: [:]) { result, day in
                for (type, count) in day.sessionCountsByType { result[type, default: 0] += count }
            },
            mealCount: days.reduce(0) { $0 + $1.mealCount },
            treatCount: days.reduce(0) { $0 + $1.treatCount },
            impulseCount: days.reduce(0) { $0 + $1.impulseCount },
            impulseDayCount: days.filter { $0.impulseCount > 0 }.count,
            durationByType: durationByType,
            emotions: emotionCounts
                .map { EmotionCount(emotion: $0.key, count: $0.value, dayCount: $0.value) }
                .sorted { $0.count == $1.count ? $0.emotion.rawValue < $1.emotion.rawValue : $0.count > $1.count }
        )
    }

    /// Days grouped by how long that night was. Buckets are the same coarse,
    /// fixed stretches `sleepDurationBuckets` uses — not targets, not
    /// recommendations.
    static func daysBySleepDuration(_ days: [DayAggregate]) -> [DayContextGroup] {
        sleepDurationBuckets.compactMap { bucket in
            let matching = days.filter { day in
                guard let duration = day.sleepDuration else { return false }
                return bucket.range.contains(duration)
            }
            guard !matching.isEmpty else { return nil }
            return describe(days: matching, key: bucket.label, label: bucket.label)
        }
    }

    /// Days grouped by the subjective rating of that night, where one was
    /// given. Days with no rating are left out — not folded into "нормально".
    static func daysBySleepQuality(_ days: [DayAggregate]) -> [DayContextGroup] {
        SleepQuality.orderedCases.compactMap { quality in
            let matching = days.filter { $0.sleepQuality == quality }
            guard !matching.isEmpty else { return nil }
            return describe(days: matching, key: quality.rawValue, label: "\(quality.emoji) \(quality.label)")
        }
    }

    /// Days grouped by their support mark. Unmarked days are their own
    /// group, labelled as such — they are never counted as "не принято".
    static func daysBySupport(_ days: [DayAggregate]) -> [DayContextGroup] {
        var groups = SupportStatus.allCases.compactMap { status -> DayContextGroup? in
            let matching = days.filter { $0.support == status }
            guard !matching.isEmpty else { return nil }
            return describe(days: matching, key: status.rawValue, label: "\(status.glyph) \(status.label)")
        }
        let unmarked = days.filter { $0.support == nil }
        if !unmarked.isEmpty {
            groups.append(
                describe(
                    days: unmarked,
                    key: "unmarked",
                    label: L("— Не отмечено", "— Not recorded")
                )
            )
        }
        return groups
    }

    /// Menstruation days against the rest. Only what was recorded counts as
    /// a period day — nothing is predicted from an assumed cycle.
    static func daysByPeriod(_ days: [DayAggregate]) -> [DayContextGroup] {
        let period = days.filter(\.isPeriodDay)
        let other = days.filter { !$0.isPeriodDay && $0.cycleDay != nil }
        var groups: [DayContextGroup] = []
        if !period.isEmpty {
            groups.append(describe(days: period, key: "period", label: L("🌸 Дни менструации", "🌸 Period days")))
        }
        if !other.isEmpty {
            groups.append(describe(days: other, key: "other", label: L("Остальные дни цикла", "Other cycle days")))
        }
        return groups
    }

    /// The same coarse cycle stretches the rest of the app uses.
    static func daysByCycleStretch(_ days: [DayAggregate]) -> [DayContextGroup] {
        let ranges: [ClosedRange<Int>] = [1...5, 6...13, 14...18, 19...23, 24...45]
        return ranges.compactMap { range in
            let matching = days.filter { day in
                guard let cycle = day.cycleDay else { return false }
                return range.contains(cycle)
            }
            guard !matching.isEmpty else { return nil }
            let label = L("Дни \(range.lowerBound)–\(range.upperBound)", "Days \(range.lowerBound)–\(range.upperBound)")
            return describe(days: matching, key: label, label: label)
        }
    }

    /// Days that held at least one impulse of a category, against days that
    /// recorded none. "Нет записей" is stated as exactly that — it is not
    /// evidence that there were no impulses.
    static func daysByImpulse(_ days: [DayAggregate], category: ImpulseCategory? = nil) -> [DayContextGroup] {
        func count(_ day: DayAggregate) -> Int {
            guard let category else { return day.impulseCount }
            return day.impulsesByCategory[category] ?? 0
        }
        let withImpulse = days.filter { count($0) > 0 }
        let without = days.filter { count($0) == 0 }
        var groups: [DayContextGroup] = []
        if !withImpulse.isEmpty {
            let label = category.map { L("Дни с отметкой «\($0.label)»", "Days with a “\($0.label)” mark") }
                ?? L("Дни с отметками импульсов", "Days with impulse marks")
            groups.append(describe(days: withImpulse, key: "with", label: label))
        }
        if !without.isEmpty {
            groups.append(
                describe(
                    days: without,
                    key: "without",
                    label: L("Дни без таких отметок", "Days without such marks")
                )
            )
        }
        return groups
    }

    /// Time and state by type of session — отдых, обязательная работа,
    /// учёба, and the untyped older sessions as their own row.
    ///
    /// The per-type figures are day-level too: a day counts once for each
    /// type it actually held, so a long день учёбы with many check-ins
    /// doesn't drown out a quiet one.
    static func daysBySessionType(_ days: [DayAggregate]) -> [DayContextGroup] {
        let types: [SessionType?] = SessionType.allCases.map { $0 } + [nil]
        return types.compactMap { type in
            let matching = days.filter { $0.duration(of: type) > 0 }
            guard !matching.isEmpty else { return nil }
            return describe(
                days: matching,
                key: type?.rawValue ?? "unassigned",
                label: "\(SessionType.emoji(for: type)) \(SessionType.label(for: type))"
            )
        }
    }

    // MARK: - The day's own state

    /// The «Состояние дня» block, assembled from the day summary the diary
    /// already computed plus the day's sleep. One function, so the card, the
    /// overall chart and the export can never disagree about a day.
    static func dayState(summary: DailySummary, sleep: SleepDaySummary?) -> DayState {
        var durationByType: [SessionType?: TimeInterval] = [:]
        for stats in summary.sessionTypes {
            durationByType[stats.type, default: 0] += stats.activeDuration
        }
        return DayState(
            date: summary.date,
            averageMood: summary.moodStats.average,
            moodCount: summary.moodStats.checkInCount,
            sleepDuration: sleep?.nightTotal,
            napDuration: sleep?.napTotal ?? 0,
            sleepQuality: sleep?.quality,
            cycleDay: summary.cycleDay,
            isPeriodDay: summary.isPeriodDay,
            support: summary.support,
            emotions: summary.distinctEmotions,
            activeDuration: summary.totalActiveDuration,
            durationByType: durationByType,
            mealCount: summary.food.mealCount,
            impulseCount: summary.impulses.count
        )
    }
}
