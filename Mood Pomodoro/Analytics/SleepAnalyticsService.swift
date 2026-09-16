//
//  SleepAnalyticsService.swift
//  Mood Pomodoro
//

import Foundation

/// Sleep alongside everything else the diary knows. Pure functions over
/// plain arrays, like the rest of `AnalyticsService`.
///
/// The one rule that shapes every function here: **a night and a day are put
/// side by side, never joined by a cause.** Sleep is grouped into coarse
/// stretches, the day that followed each night is described, and the UI says
/// "в дни после таких ночей среднее было X". Nothing in this file decides
/// that short sleep lowered anything, and nothing grades a night: there is
/// no "poor deep sleep", no "not enough REM", and no sleep score.
extension AnalyticsService {

    // MARK: - Period figures

    /// How the period's nights looked — averages and extremes, nothing more.
    static func sleepStatistics(
        sessions: [SleepSessionSummary],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> SleepPeriodStatistics? {
        let inPeriod = SleepAggregationService.resolveOverlaps(sessions: sessions).filter { !$0.isSuperseded && $0.day >= interval.start && $0.day < interval.end }
        guard !inPeriod.isEmpty else { return nil }

        let nights = inPeriod.filter { $0.kind == .night }
        let naps = inPeriod.filter { $0.kind == .nap }
        // One figure per day, so two nights filed to the same day (a manual
        // entry next to an imported one) can't weight that day twice.
        let byDay = Dictionary(grouping: nights) { calendar.startOfDay(for: $0.day) }
        let dailyTotals = byDay.mapValues { group in group.reduce(0) { $0 + $1.totalSleep } }

        let staged = nights.filter(\.hasStageDetail)
        func averageStage(_ stage: SleepStage) -> TimeInterval? {
            guard !staged.isEmpty else { return nil }
            return staged.reduce(0) { $0 + $1.duration(of: stage) } / Double(staged.count)
        }

        return SleepPeriodStatistics(
            nightCount: dailyTotals.count,
            averageSleep: dailyTotals.isEmpty ? nil : dailyTotals.values.reduce(0, +) / Double(dailyTotals.count),
            shortest: nights.min { $0.totalSleep < $1.totalSleep },
            longest: nights.max { $0.totalSleep < $1.totalSleep },
            stagedNightCount: staged.count,
            averageDeep: averageStage(.deep),
            averageREM: averageStage(.rem),
            averageCore: averageStage(.core),
            averageAwake: staged.isEmpty ? nil : staged.reduce(0) { $0 + $1.awake } / Double(staged.count),
            napCount: naps.count,
            averageNap: naps.isEmpty ? nil : naps.reduce(0) { $0 + $1.totalSleep } / Double(naps.count),
            points: dailyTotals
                .map { SleepDayPoint(day: $0.key, totalSleep: $0.value) }
                .sorted { $0.day < $1.day }
        )
    }

    // MARK: - Sleep beside the day that followed

    /// Coarse, fixed stretches of night length. Not targets, not
    /// recommendations — buckets to group observations into.
    static let sleepDurationBuckets: [(label: String, range: Range<TimeInterval>)] = [
        (L("Меньше 6 часов", "Under 6 hours"), 0..<(6 * 3600)),
        (L("6–8 часов", "6–8 hours"), (6 * 3600)..<(8 * 3600)),
        (L("Больше 8 часов", "Over 8 hours"), (8 * 3600)..<TimeInterval.greatestFiniteMagnitude)
    ]

    /// Each bucket of night length, described by the days that followed
    /// those nights. Every figure carries its own sample size so the UI can
    /// say "недостаточно данных" instead of showing a confident average.
    static func sleepAssociations(
        sessions: [SleepSessionSummary],
        checkIns: [CheckIn],
        hungerEntries: [HungerEntry] = [],
        foodEntries: [FoodEntry] = [],
        focusSessions: [FocusSession] = [],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [SleepAssociationGroup] {
        let totals = nightlyTotals(sessions: sessions, in: interval, calendar: calendar)
        guard !totals.isEmpty else { return [] }

        return sleepDurationBuckets.compactMap { bucket in
            let days = Set(totals.filter { bucket.range.contains($0.value) }.keys)
            guard !days.isEmpty else { return nil }
            return group(
                key: bucket.label,
                label: bucket.label,
                days: days,
                checkIns: checkIns,
                hungerEntries: hungerEntries,
                foodEntries: foodEntries,
                focusSessions: focusSessions,
                calendar: calendar
            )
        }
    }

    /// The same description, split by how much deep sleep a night held
    /// relative to the user's *own* median — never against a published norm,
    /// which would be a medical claim the app has no business making.
    static func deepSleepAssociations(
        sessions: [SleepSessionSummary],
        checkIns: [CheckIn],
        focusSessions: [FocusSession] = [],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [SleepAssociationGroup] {
        let staged = SleepAggregationService.resolveOverlaps(sessions: sessions).filter { !$0.isSuperseded && $0.kind == .night && $0.hasStageDetail && interval.contains($0.day) }
        guard staged.count >= minimumSampleSize * 2 else { return [] }
        let values = staged.map { $0.duration(of: .deep) }.sorted()
        let median = values[values.count / 2]

        let above = Set(staged.filter { $0.duration(of: .deep) >= median }.map { calendar.startOfDay(for: $0.day) })
        let below = Set(staged.filter { $0.duration(of: .deep) < median }.map { calendar.startOfDay(for: $0.day) })

        return [
            (L("Больше глубокого сна, чем обычно", "More deep sleep than usual"), above),
            (L("Меньше глубокого сна, чем обычно", "Less deep sleep than usual"), below)
        ].compactMap { label, days in
            guard !days.isEmpty else { return nil }
            return group(
                key: label,
                label: label,
                days: days,
                checkIns: checkIns,
                hungerEntries: [],
                foodEntries: [],
                focusSessions: focusSessions,
                calendar: calendar
            )
        }
    }

    /// Average night length by stretch of the cycle. Descriptive, like every
    /// other cycle grouping in the app — no medical conclusions.
    static func sleepByCycleStretch(
        sessions: [SleepSessionSummary],
        cycleEntries: [CycleEntry],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [SleepCycleBucket] {
        guard !cycleEntries.isEmpty else { return [] }
        let totals = nightlyTotals(sessions: sessions, in: interval, calendar: calendar)
        guard !totals.isEmpty else { return [] }

        let ranges: [ClosedRange<Int>] = [1...5, 6...13, 14...18, 19...23, 24...45]
        return ranges.compactMap { range in
            let matching = totals.filter { day, _ in
                guard let cycle = cycleDay(for: day, entries: cycleEntries, calendar: calendar) else { return false }
                return range.contains(cycle)
            }
            guard !matching.isEmpty else { return nil }
            return SleepCycleBucket(
                label: L("Дни \(range.lowerBound)–\(range.upperBound)", "Days \(range.lowerBound)–\(range.upperBound)"),
                dayRange: range,
                averageSleep: matching.values.reduce(0, +) / Double(matching.count),
                nightCount: matching.count
            )
        }
    }

    // MARK: -

    /// One total per day, so a day is never counted twice.
    private static func nightlyTotals(
        sessions: [SleepSessionSummary],
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for session in SleepAggregationService.resolveOverlaps(sessions: sessions) where !session.isSuperseded && session.kind == .night && interval.contains(session.day) {
            totals[calendar.startOfDay(for: session.day), default: 0] += session.totalSleep
        }
        return totals
    }

    private static func group(
        key: String,
        label: String,
        days: Set<Date>,
        checkIns: [CheckIn],
        hungerEntries: [HungerEntry],
        foodEntries: [FoodEntry],
        focusSessions: [FocusSession],
        calendar: Calendar
    ) -> SleepAssociationGroup {
        let dayCheckIns = checkIns.filter { days.contains(calendar.startOfDay(for: $0.timestamp)) }
        let dayHunger = hungerEntries.filter { days.contains(calendar.startOfDay(for: $0.eventDate)) }
        let dayFood = foodEntries.filter { days.contains(calendar.startOfDay(for: $0.eventDate)) }
        let daySessions = focusSessions.filter { days.contains(calendar.startOfDay(for: $0.startDate)) }

        let energies = dayCheckIns.compactMap(\.energy)
        let motivations = dayCheckIns.compactMap(\.motivation)
        let hungers = dayHunger.compactMap(\.hunger)
        let appetites = dayHunger.compactMap(\.appetite)

        let aggregates = dayAggregates(checkIns: dayCheckIns, hungerEntries: dayHunger, calendar: calendar)
        let figures = describe(days: aggregates, key: key, label: label)
        return SleepAssociationGroup(
            key: key,
            label: label,
            dayCount: days.count,
            averageMood: figures.scales.first { $0.metric == .mood }?.average,
            moodCount: dayCheckIns.count,
            averageEnergy: figures.scales.first { $0.metric == .energy }?.average,
            energyCount: energies.count,
            averageMotivation: figures.scales.first { $0.metric == .motivation }?.average,
            motivationCount: motivations.count,
            averageHunger: figures.scales.first { $0.metric == .hunger }?.average,
            hungerCount: hungers.count,
            averageAppetite: figures.scales.first { $0.metric == .appetite }?.average,
            appetiteCount: appetites.count,
            mealCount: dayFood.count,
            treatCount: dayFood.filter { $0.category == .treat }.count,
            activityDuration: daySessions.reduce(0) { $0 + $1.activeWorkDuration() }
        )
    }
}

// MARK: - Result types

/// A period's nights, as recorded. No score, no target, no verdict.
struct SleepPeriodStatistics {
    let nightCount: Int
    let averageSleep: TimeInterval?
    let shortest: SleepSessionSummary?
    let longest: SleepSessionSummary?
    /// How many nights had real stage detail — the rest were a single
    /// undifferentiated "asleep" block, and stage averages exclude them.
    let stagedNightCount: Int
    let averageDeep: TimeInterval?
    let averageREM: TimeInterval?
    let averageCore: TimeInterval?
    let averageAwake: TimeInterval?
    let napCount: Int
    let averageNap: TimeInterval?
    let points: [SleepDayPoint]

    var hasEnoughData: Bool { nightCount >= AnalyticsService.minimumSampleSize }
    var hasStageDetail: Bool { stagedNightCount > 0 }
}

/// One night's length on the month chart.
struct SleepDayPoint: Identifiable {
    var id: Date { day }
    let day: Date
    let totalSleep: TimeInterval

    var hours: Double { totalSleep / 3600 }
}

/// What the days following one kind of night looked like. Co-occurrence
/// only — the UI must phrase these as observations, never as effects.
struct SleepAssociationGroup: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let dayCount: Int
    let averageMood: Double?
    let moodCount: Int
    let averageEnergy: Double?
    let energyCount: Int
    let averageMotivation: Double?
    let motivationCount: Int
    let averageHunger: Double?
    let hungerCount: Int
    let averageAppetite: Double?
    let appetiteCount: Int
    let mealCount: Int
    let treatCount: Int
    let activityDuration: TimeInterval

    var hasEnoughData: Bool { dayCount >= AnalyticsService.minimumSampleSize }
}

/// Night length by stretch of the cycle.
struct SleepCycleBucket: Identifiable {
    var id: String { label }
    let label: String
    let dayRange: ClosedRange<Int>
    let averageSleep: TimeInterval
    let nightCount: Int

    var hasEnoughData: Bool { nightCount >= AnalyticsService.minimumSampleSize }
}
