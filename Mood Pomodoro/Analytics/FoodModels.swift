//
//  FoodModels.swift
//  Mood Pomodoro
//

import Foundation

/// Aggregated food / hunger / appetite results, in the same contract as
/// `DiaryModels`: views render these and never compute a figure themselves.
///
/// This is not a calorie tracker and not a diet app. Nothing here scores a
/// day, grades a category, counts a streak or says whether the user ate
/// "well". Every figure answers "как я ем и как это связано с состоянием",
/// and every group carries its own sample size so the UI can say
/// "недостаточно данных" instead of showing a confident-looking average.

/// One food record placed on the day's clock.
struct FoodDayEntry: Identifiable {
    let id: UUID
    let eventDate: Date
    let category: FoodCategory
    let mealDensity: MealDensity?
    let taste: TasteRating?
    let treatType: TreatType?
    let treatAmount: TreatAmount?
    let fullness: Fullness?
    let desc: String?
    let note: String?

    /// "Полезная · Плотно · Вкусно" — only what was answered.
    var detailLine: String {
        var parts = [category.label]
        if let mealDensity { parts.append(mealDensity.label) }
        if let taste { parts.append(taste.label) }
        if let treatType { parts.append(treatType.label) }
        if let treatAmount { parts.append(treatAmount.label) }
        return parts.joined(separator: " · ")
    }
}

/// One hunger/appetite record placed on the day's clock. Either scale can be
/// nil — that means it wasn't answered, not that it was in the middle.
struct HungerDayEntry: Identifiable {
    let id: UUID
    let eventDate: Date
    let hunger: HungerLevel?
    let appetite: AppetiteLevel?
    let note: String?

    var summaryLine: String {
        var parts: [String] = []
        if let hunger { parts.append(L("Голод: \(Int(hunger.scale))/5", "Hunger: \(Int(hunger.scale))/5")) }
        if let appetite { parts.append(L("Аппетит: \(Int(appetite.scale))/5", "Appetite: \(Int(appetite.scale))/5")) }
        return parts.joined(separator: " · ")
    }
}

/// How many entries fell in one category, for a day or a month. A count,
/// nothing else — deliberately no share, no rank, no "target".
struct FoodCategoryCount: Identifiable {
    var id: String { category.rawValue }
    let category: FoodCategory
    let count: Int
}

/// The treat drawer broken out by type and by amount, for a month.
struct TreatBreakdown {
    let byType: [(type: TreatType, count: Int)]
    let byAmount: [(amount: TreatAmount, count: Int)]
    let total: Int

    static let empty = TreatBreakdown(byType: [], byAmount: [], total: 0)
    var isEmpty: Bool { total == 0 }
}

/// A day's food block: what was eaten and what hunger/appetite was recorded
/// around it. `averageHungerBeforeMeals` only counts meals that actually had
/// a hunger entry shortly before — meals without one are simply not in it.
struct FoodDaySummary {
    let entries: [FoodDayEntry]
    let hungerEntries: [HungerDayEntry]
    let categoryCounts: [FoodCategoryCount]
    let averageHunger: Double?
    let averageAppetite: Double?
    /// Mean hunger recorded within `AnalyticsService.mealLinkWindow` before a
    /// meal, over the meals that had such a record.
    let averageHungerBeforeMeals: Double?
    let mealsWithHungerBefore: Int

    static let empty = FoodDaySummary(
        entries: [],
        hungerEntries: [],
        categoryCounts: [],
        averageHunger: nil,
        averageAppetite: nil,
        averageHungerBeforeMeals: nil,
        mealsWithHungerBefore: 0
    )

    var mealCount: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty && hungerEntries.isEmpty }
}

/// A named stretch of the day, for "когда я обычно голодна".
enum DayPart: String, CaseIterable, Identifiable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    var id: String { rawValue }

    /// Fixed, coarse and descriptive. Night wraps midnight, so it is the
    /// one bucket tested as "outside the others".
    var hours: Range<Int> {
        switch self {
        case .morning: return 5..<12
        case .afternoon: return 12..<17
        case .evening: return 17..<23
        case .night: return 23..<29
        }
    }

    var label: String {
        switch self {
        case .morning: return L("Утро", "Morning")
        case .afternoon: return L("День", "Afternoon")
        case .evening: return L("Вечер", "Evening")
        case .night: return L("Ночь", "Night")
        }
    }

    var emoji: String {
        switch self {
        case .morning: return "🌅"
        case .afternoon: return "☀️"
        case .evening: return "🌆"
        case .night: return "🌙"
        }
    }

    static func containing(hour: Int) -> DayPart {
        allCases.first { $0.hours.contains(hour) || $0.hours.contains(hour + 24) } ?? .night
    }
}

/// One group's hunger and appetite side by side — by time of day, by
/// activity, by cycle stretch, by mood. Deliberately one struct: the two
/// scales are always reported separately and never averaged together.
struct HungerAppetiteGroup: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    var emoji: String?
    let averageHunger: Double?
    let hungerCount: Int
    let averageAppetite: Double?
    let appetiteCount: Int
    /// Food records in the same group, when the grouping has any.
    var foodCount: Int = 0
    var treatCount: Int = 0

    var sampleSize: Int { max(hungerCount, appetiteCount) }
    var hasEnoughData: Bool { sampleSize >= AnalyticsService.minimumSampleSize }
    var isEmpty: Bool { hungerCount == 0 && appetiteCount == 0 && foodCount == 0 }
}

/// What the other scales looked like around meals of one category. Purely
/// observational — "в твоих данных после таких записей чаще встречалось…",
/// never "обычная еда улучшает настроение".
struct FoodStateObservation: Identifiable {
    var id: String { category.rawValue }
    let category: FoodCategory
    let mealCount: Int
    let averageMoodAfter: Double?
    let moodSampleCount: Int
    let averageEnergyAfter: Double?
    let energySampleCount: Int
    let averageHungerBefore: Double?
    let hungerSampleCount: Int

    var hasEnoughMood: Bool { moodSampleCount >= AnalyticsService.minimumSampleSize }
    var hasEnoughEnergy: Bool { energySampleCount >= AnalyticsService.minimumSampleSize }
    var hasEnoughHunger: Bool { hungerSampleCount >= AnalyticsService.minimumSampleSize }
}

/// How full she was after eating, when she said. Counts only.
struct FullnessCount: Identifiable {
    var id: String { fullness.rawValue }
    let fullness: Fullness
    let count: Int
}

/// Everything the month's food block shows.
struct FoodMonthSummary {
    let mealCount: Int
    let categoryCounts: [FoodCategoryCount]
    let treats: TreatBreakdown
    let fullness: [FullnessCount]
    let averageHunger: Double?
    let hungerCount: Int
    let averageAppetite: Double?
    let appetiteCount: Int
    let averageHungerBeforeMeals: Double?
    let mealsWithHungerBefore: Int
    /// Hunger/appetite by stretch of the day.
    let byDayPart: [HungerAppetiteGroup]
    /// Hunger/appetite grouped the way `cycleMoodBuckets` groups mood.
    let byCycleStretch: [HungerAppetiteGroup]
    let byActivity: [HungerAppetiteGroup]
    let byMood: [HungerAppetiteGroup]
    let aroundMeals: [FoodStateObservation]

    static let empty = FoodMonthSummary(
        mealCount: 0,
        categoryCounts: [],
        treats: .empty,
        fullness: [],
        averageHunger: nil,
        hungerCount: 0,
        averageAppetite: nil,
        appetiteCount: 0,
        averageHungerBeforeMeals: nil,
        mealsWithHungerBefore: 0,
        byDayPart: [],
        byCycleStretch: [],
        byActivity: [],
        byMood: [],
        aroundMeals: []
    )

    var isEmpty: Bool { mealCount == 0 && hungerCount == 0 && appetiteCount == 0 }
    var hasHungerOrAppetite: Bool { hungerCount > 0 || appetiteCount > 0 }
}
