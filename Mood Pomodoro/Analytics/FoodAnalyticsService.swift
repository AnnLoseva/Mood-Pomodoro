//
//  FoodAnalyticsService.swift
//  Mood Pomodoro
//

import Foundation

/// Food, hunger and appetite aggregation. Lives on `AnalyticsService` for
/// the same reason the diary's does: one place turns records into numbers,
/// and it stays pure (plain arrays in, value types out) so all of this is
/// testable without a `ModelContext`.
///
/// Three rules this file is built on:
/// * Hunger and appetite are **never** mixed into one scale, averaged
///   together, or derived from each other. Every group reports them side by
///   side with separate sample counts.
/// * Records are placed by `eventDate` — when the food or the hunger
///   happened — never by `createdAt`.
/// * Linking is by timestamp proximity only, inside
///   `mealLinkWindow`, and produces co-occurrence, not cause. Nothing here
///   returns a sentence; the UI phrases these as observations.
extension AnalyticsService {

    /// How close in time a hunger record has to be to count as "перед этой
    /// едой", and a mood/energy record as "после". Wide enough that a meal
    /// logged without an exact hunger ping still finds one, narrow enough
    /// that breakfast doesn't get attached to lunch.
    static let mealLinkWindow: TimeInterval = 90 * 60

    // MARK: - Small shared helpers

    static func averageScale<Step: ScaleStep>(_ values: [Step]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0) { $0 + $1.scale } / Double(values.count)
    }

    /// The hunger recorded closest before `date`, within `mealLinkWindow`.
    /// Nil when nothing was recorded — a meal with no hunger entry near it
    /// contributes nothing rather than a guessed middle value.
    static func hungerEntry(before date: Date, in entries: [HungerEntry]) -> HungerEntry? {
        entries
            .filter { $0.hunger != nil && $0.eventDate <= date && date.timeIntervalSince($0.eventDate) <= mealLinkWindow }
            .max { $0.eventDate < $1.eventDate }
    }

    // MARK: - Day

    static func foodDaySummary(
        date: Date,
        foodEntries: [FoodEntry],
        hungerEntries: [HungerEntry],
        calendar: Calendar = .current
    ) -> FoodDaySummary {
        let meals = foodEntries
            .filter { calendar.isDate($0.eventDate, inSameDayAs: date) }
            .sorted { $0.eventDate < $1.eventDate }
        let hunger = hungerEntries
            .filter { !$0.isEmpty && calendar.isDate($0.eventDate, inSameDayAs: date) }
            .sorted { $0.eventDate < $1.eventDate }
        guard !meals.isEmpty || !hunger.isEmpty else { return .empty }

        // Hunger before a meal may have been recorded late the previous
        // evening for a meal just after midnight, so it is looked up in the
        // *whole* set rather than in the day's own entries.
        let before = meals.compactMap { hungerEntry(before: $0.eventDate, in: hungerEntries)?.hunger }

        return FoodDaySummary(
            entries: meals.map(dayEntry),
            hungerEntries: hunger.map(dayEntry),
            categoryCounts: categoryCounts(of: meals),
            averageHunger: averageScale(hunger.compactMap(\.hunger)),
            averageAppetite: averageScale(hunger.compactMap(\.appetite)),
            averageHungerBeforeMeals: averageScale(before),
            mealsWithHungerBefore: before.count
        )
    }

    // MARK: - Month

    static func foodMonthSummary(
        in interval: DateInterval,
        foodEntries: [FoodEntry],
        hungerEntries: [HungerEntry],
        checkIns: [CheckIn] = [],
        sessions: [FocusSession] = [],
        cycleEntries: [CycleEntry] = [],
        calendar: Calendar = .current
    ) -> FoodMonthSummary {
        let meals = foodEntries.filter { interval.contains($0.eventDate) }.sorted { $0.eventDate < $1.eventDate }
        let hunger = hungerEntries
            .filter { !$0.isEmpty && interval.contains($0.eventDate) }
            .sorted { $0.eventDate < $1.eventDate }
        guard !meals.isEmpty || !hunger.isEmpty else { return .empty }

        let before = meals.compactMap { hungerEntry(before: $0.eventDate, in: hungerEntries)?.hunger }
        let periodCheckIns = checkIns.filter { interval.contains($0.timestamp) }

        return FoodMonthSummary(
            mealCount: meals.count,
            categoryCounts: categoryCounts(of: meals),
            treats: treatBreakdown(of: meals),
            fullness: fullnessCounts(of: meals),
            averageHunger: averageScale(hunger.compactMap(\.hunger)),
            hungerCount: hunger.compactMap(\.hunger).count,
            averageAppetite: averageScale(hunger.compactMap(\.appetite)),
            appetiteCount: hunger.compactMap(\.appetite).count,
            averageHungerBeforeMeals: averageScale(before),
            mealsWithHungerBefore: before.count,
            byDayPart: hungerByDayPart(hungerEntries: hunger, foodEntries: meals, calendar: calendar),
            byCycleStretch: hungerByCycleStretch(
                hungerEntries: hunger,
                foodEntries: meals,
                cycleEntries: cycleEntries,
                calendar: calendar
            ),
            byActivity: hungerByActivity(hungerEntries: hunger, sessions: sessions),
            byMood: hungerByMood(hungerEntries: hunger, checkIns: periodCheckIns),
            aroundMeals: observationsAroundMeals(
                meals: meals,
                checkIns: checkIns,
                hungerEntries: hungerEntries
            )
        )
    }

    // MARK: - Counts

    static func categoryCounts(of meals: [FoodEntry]) -> [FoodCategoryCount] {
        FoodCategory.allCases.compactMap { category in
            let count = meals.filter { $0.category == category }.count
            return count == 0 ? nil : FoodCategoryCount(category: category, count: count)
        }
    }

    static func treatBreakdown(of meals: [FoodEntry]) -> TreatBreakdown {
        let treats = meals.filter { $0.category == .treat }
        guard !treats.isEmpty else { return .empty }
        return TreatBreakdown(
            byType: TreatType.allCases.compactMap { type in
                let count = treats.filter { $0.treatType == type }.count
                return count == 0 ? nil : (type: type, count: count)
            },
            byAmount: TreatAmount.allCases.compactMap { amount in
                let count = treats.filter { $0.treatAmount == amount }.count
                return count == 0 ? nil : (amount: amount, count: count)
            },
            total: treats.count
        )
    }

    static func fullnessCounts(of meals: [FoodEntry]) -> [FullnessCount] {
        Fullness.orderedCases.compactMap { level in
            let count = meals.filter { $0.fullness == level }.count
            return count == 0 ? nil : FullnessCount(fullness: level, count: count)
        }
    }

    // MARK: - Groupings

    /// Hunger and appetite by stretch of the day, with how much food was
    /// recorded in the same stretch alongside them.
    static func hungerByDayPart(
        hungerEntries: [HungerEntry],
        foodEntries: [FoodEntry],
        calendar: Calendar = .current
    ) -> [HungerAppetiteGroup] {
        DayPart.allCases.compactMap { part in
            let matching = hungerEntries.filter {
                DayPart.containing(hour: calendar.component(.hour, from: $0.eventDate)) == part
            }
            let meals = foodEntries.filter {
                DayPart.containing(hour: calendar.component(.hour, from: $0.eventDate)) == part
            }
            let group = group(
                key: part.rawValue,
                label: part.label,
                emoji: part.emoji,
                entries: matching,
                meals: meals
            )
            return group.isEmpty ? nil : group
        }
    }

    /// Same fixed, descriptive stretches `cycleMoodBuckets` uses — not
    /// phases, and never a medical statement about any of them.
    static func hungerByCycleStretch(
        hungerEntries: [HungerEntry],
        foodEntries: [FoodEntry],
        cycleEntries: [CycleEntry],
        calendar: Calendar = .current
    ) -> [HungerAppetiteGroup] {
        guard !cycleEntries.isEmpty else { return [] }
        let ranges: [ClosedRange<Int>] = [1...5, 6...13, 14...18, 19...23, 24...45]
        var groups: [HungerAppetiteGroup] = []
        for range in ranges {
            let matching = hungerEntries.filter { entry in
                guard let day = cycleDay(for: entry.eventDate, entries: cycleEntries, calendar: calendar) else { return false }
                return range.contains(day)
            }
            let meals = foodEntries.filter { meal in
                guard let day = cycleDay(for: meal.eventDate, entries: cycleEntries, calendar: calendar) else { return false }
                return range.contains(day)
            }
            let group = group(
                key: "cycle-\(range.lowerBound)",
                label: L("Дни \(range.lowerBound)–\(range.upperBound)", "Days \(range.lowerBound)–\(range.upperBound)"),
                emoji: nil,
                entries: matching,
                meals: meals
            )
            if !group.isEmpty { groups.append(group) }
        }
        return groups
    }

    /// Hunger/appetite recorded while a session was running, by activity. A
    /// record made outside every session belongs to no activity and is
    /// simply absent here rather than lumped into one.
    static func hungerByActivity(
        hungerEntries: [HungerEntry],
        sessions: [FocusSession],
        now: Date = .now
    ) -> [HungerAppetiteGroup] {
        guard !sessions.isEmpty else { return [] }
        var byActivity: [String: [HungerEntry]] = [:]
        for entry in hungerEntries {
            guard let session = sessions.first(where: { session in
                let end = session.endDate ?? now
                return session.startDate <= entry.eventDate && entry.eventDate <= end
            }) else { continue }
            byActivity[canonicalData(session.activity), default: []].append(entry)
        }
        return byActivity
            .map { activity, entries in
                group(key: activity, label: Ldata(activity), emoji: nil, entries: entries, meals: [])
            }
            .sorted { $0.sampleSize > $1.sampleSize }
    }

    /// Hunger/appetite grouped by the mood recorded nearest in time, within
    /// `mealLinkWindow`. Co-occurrence only.
    static func hungerByMood(
        hungerEntries: [HungerEntry],
        checkIns: [CheckIn]
    ) -> [HungerAppetiteGroup] {
        guard !checkIns.isEmpty else { return [] }
        var byMood: [Mood: [HungerEntry]] = [:]
        for entry in hungerEntries {
            let nearest = checkIns
                .filter { abs($0.timestamp.timeIntervalSince(entry.eventDate)) <= mealLinkWindow }
                .min { abs($0.timestamp.timeIntervalSince(entry.eventDate)) < abs($1.timestamp.timeIntervalSince(entry.eventDate)) }
            guard let mood = nearest?.mood else { continue }
            byMood[mood, default: []].append(entry)
        }
        return Mood.orderedCases.compactMap { mood in
            guard let entries = byMood[mood] else { return nil }
            let group = group(key: mood.rawValue, label: mood.label, emoji: mood.emoji, entries: entries, meals: [])
            return group.isEmpty ? nil : group
        }
    }

    /// What the other scales looked like around meals of each category:
    /// hunger inside `mealLinkWindow` before, mood and energy inside it
    /// after. Observational — the UI must not phrase these as effects.
    static func observationsAroundMeals(
        meals: [FoodEntry],
        checkIns: [CheckIn],
        hungerEntries: [HungerEntry]
    ) -> [FoodStateObservation] {
        FoodCategory.allCases.compactMap { category in
            let matching = meals.filter { $0.category == category }
            guard !matching.isEmpty else { return nil }

            var moods: [Mood] = []
            var energies: [EnergyLevel] = []
            var hungers: [HungerLevel] = []
            for meal in matching {
                let after = checkIns.filter {
                    $0.timestamp >= meal.eventDate
                        && $0.timestamp.timeIntervalSince(meal.eventDate) <= mealLinkWindow
                }
                moods.append(contentsOf: after.map(\.mood))
                energies.append(contentsOf: after.compactMap(\.energy))
                if let hunger = hungerEntry(before: meal.eventDate, in: hungerEntries)?.hunger {
                    hungers.append(hunger)
                }
            }
            return FoodStateObservation(
                category: category,
                mealCount: matching.count,
                averageMoodAfter: averageScale(moods),
                moodSampleCount: moods.count,
                averageEnergyAfter: averageScale(energies),
                energySampleCount: energies.count,
                averageHungerBefore: averageScale(hungers),
                hungerSampleCount: hungers.count
            )
        }
    }

    // MARK: - Timeline rows

    static func foodTimelineEvent(for entry: FoodEntry) -> TimelineEvent {
        // The icon column carries the category's illustration, so the title
        // doesn't repeat it as an emoji.
        let title = entry.desc.flatMap { $0.isEmpty ? nil : $0 } ?? entry.detailLine
        var subtitleParts: [String] = []
        if entry.desc != nil { subtitleParts.append(entry.detailLine) }
        if let fullness = entry.fullness {
            subtitleParts.append(L("После: \(fullness.label)", "After: \(fullness.label)"))
        }
        if let note = entry.note, !note.isEmpty { subtitleParts.append(note) }
        return TimelineEvent(
            id: "food-\(entry.id.uuidString)",
            timestamp: entry.eventDate,
            kind: .food,
            title: title,
            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
            mood: nil,
            target: .food(entry.id),
            imageName: entry.category.imageName
        )
    }

    static func hungerTimelineEvent(for entry: HungerEntry) -> TimelineEvent {
        TimelineEvent(
            id: "hunger-\(entry.id.uuidString)",
            timestamp: entry.eventDate,
            kind: .hunger,
            title: entry.summaryLine,
            subtitle: entry.note,
            mood: nil,
            target: .hunger(entry.id),
            // Hunger leads the row when it was answered; a record with only
            // an appetite shows that one instead.
            imageName: entry.hunger?.imageName ?? entry.appetite?.imageName
        )
    }

    // MARK: -

    private static func group(
        key: String,
        label: String,
        emoji: String?,
        entries: [HungerEntry],
        meals: [FoodEntry]
    ) -> HungerAppetiteGroup {
        let hungers = entries.compactMap(\.hunger)
        let appetites = entries.compactMap(\.appetite)
        return HungerAppetiteGroup(
            key: key,
            label: label,
            emoji: emoji,
            averageHunger: averageScale(hungers),
            hungerCount: hungers.count,
            averageAppetite: averageScale(appetites),
            appetiteCount: appetites.count,
            foodCount: meals.count,
            treatCount: meals.filter { $0.category == .treat }.count
        )
    }

    private static func dayEntry(_ entry: FoodEntry) -> FoodDayEntry {
        FoodDayEntry(
            id: entry.id,
            eventDate: entry.eventDate,
            category: entry.category,
            mealDensity: entry.mealDensity,
            taste: entry.taste,
            treatType: entry.treatType,
            treatAmount: entry.treatAmount,
            fullness: entry.fullness,
            desc: entry.desc,
            note: entry.note
        )
    }

    private static func dayEntry(_ entry: HungerEntry) -> HungerDayEntry {
        HungerDayEntry(
            id: entry.id,
            eventDate: entry.eventDate,
            hunger: entry.hunger,
            appetite: entry.appetite,
            note: entry.note
        )
    }
}
