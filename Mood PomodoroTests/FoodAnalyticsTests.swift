//
//  FoodAnalyticsTests.swift
//  Mood PomodoroTests
//

import Foundation
import Testing
@testable import Mood_Pomodoro

/// Food, hunger and appetite. Like `DiaryAnalyticsTests`, everything here
/// runs on plain objects with a fixed-UTC calendar — no `ModelContainer`.
///
/// Three rules are what these tests exist to protect:
/// hunger and appetite never collapse into one figure, a food record never
/// holds a contradictory pair of fields, and every record is placed by when
/// it *happened* rather than when it was typed.
struct FoodAnalyticsTests {

    /// The test host is the app itself, so it inherits whatever language
    /// was last picked in the simulator. Pin Russian — the expectations
    /// below are written against the Russian labels.
    init() {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguage.storageKey)
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour, minute: minute))!
    }

    private func meal(
        _ category: FoodCategory,
        at date: Date,
        density: MealDensity? = nil,
        taste: TasteRating? = nil,
        treatType: TreatType? = nil,
        treatAmount: TreatAmount? = nil,
        fullness: Fullness? = nil,
        desc: String? = nil
    ) -> FoodEntry {
        FoodEntry(
            eventDate: date,
            category: category,
            mealDensity: density,
            taste: taste,
            treatType: treatType,
            treatAmount: treatAmount,
            fullness: fullness,
            desc: desc
        )
    }

    private func hunger(_ level: HungerLevel?, _ appetite: AppetiteLevel?, at date: Date) -> HungerEntry {
        HungerEntry(eventDate: date, hunger: level, appetite: appetite)
    }

    // MARK: - Validation (spec §9)

    @Test func aMealNeverKeepsTheFieldsOfTheOtherBranch() {
        // Scenario B: a treat carries type and amount and nothing else.
        let treat = meal(.treat, at: date(20, 20), treatType: .sweet, treatAmount: .little)
        #expect(treat.category == .treat)
        #expect(treat.treatType == .sweet)
        #expect(treat.treatAmount == .little)
        #expect(treat.mealDensity == nil)
        #expect(treat.taste == nil)

        let lunch = meal(.regular, at: date(20, 13), density: .filling, taste: .tasty)
        #expect(lunch.mealDensity == .filling)
        #expect(lunch.taste == .tasty)
        #expect(lunch.treatType == nil)
        #expect(lunch.treatAmount == nil)
    }

    /// The init must not smuggle a contradictory pair through either, even
    /// when a caller hands over both halves at once.
    @Test func contradictoryFieldsAreDroppedOnTheWayIn() {
        let entry = meal(
            .healthy,
            at: date(20, 13),
            density: .light,
            taste: .tasty,
            treatType: .salty,
            treatAmount: .tooMuch
        )
        #expect(entry.treatTypeRaw == nil)
        #expect(entry.treatAmountRaw == nil)
    }

    @Test func changingTheCategoryClearsWhatBelongedToTheOldOne() {
        let entry = meal(.regular, at: date(20, 13), density: .filling, taste: .tasty)
        entry.apply(category: .treat, mealDensity: nil, taste: nil, treatType: .sweet, treatAmount: .normal)

        #expect(entry.mealDensityRaw == nil)
        #expect(entry.tasteRaw == nil)
        #expect(entry.treatType == .sweet)
        #expect(entry.treatAmount == .normal)
    }

    // MARK: - Hunger and appetite stay apart (spec §1, §2, §18)

    @Test func hungerAndAppetiteAreIndependent() {
        let entries = [
            hunger(.hungry, .noAppetite, at: date(20, 12)),
            hunger(.notHungry, .veryHigh, at: date(20, 16))
        ]
        let summary = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: [],
            hungerEntries: entries,
            calendar: calendar
        )
        // Hunger 4 and 1 average to 2.5; appetite 1 and 5 average to 3.
        // Neither figure may borrow anything from the other.
        #expect(summary.averageHunger == 2.5)
        #expect(summary.averageAppetite == 3)
    }

    @Test func anUnansweredScaleIsAbsentRatherThanMiddling() {
        let entries = [
            hunger(.veryHungry, nil, at: date(20, 12)),
            hunger(nil, .noAppetite, at: date(20, 13))
        ]
        let summary = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: [],
            hungerEntries: entries,
            calendar: calendar
        )
        // Not (5 + 3) / 2 — the missing appetite contributes nothing at all.
        #expect(summary.averageHunger == 5)
        #expect(summary.averageAppetite == 1)
    }

    @Test func anEntryWithNeitherScaleIsIgnored() {
        let summary = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: [],
            hungerEntries: [hunger(nil, nil, at: date(20, 12))],
            calendar: calendar
        )
        #expect(summary.isEmpty)
        #expect(summary.hungerEntries.isEmpty)
    }

    // MARK: - Hunger before a meal (spec §12)

    /// Scenario A: hunger 5 / appetite 2 at 12:00, a meal at 13:00.
    @Test func hungerRecordedShortlyBeforeAMealIsLinkedToIt() {
        let hungerEntries = [hunger(.veryHungry, .low, at: date(20, 12))]
        let meals = [meal(.healthy, at: date(20, 13), density: .filling, taste: .tasty)]

        let summary = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: meals,
            hungerEntries: hungerEntries,
            calendar: calendar
        )
        #expect(summary.mealCount == 1)
        #expect(summary.mealsWithHungerBefore == 1)
        #expect(summary.averageHungerBeforeMeals == 5)

        // And the two events sit on the clock in the order they happened.
        let day = AnalyticsService.dailySummary(
            date: date(20),
            sessions: [],
            checkIns: [],
            foodEntries: meals,
            hungerEntries: hungerEntries,
            calendar: calendar
        )
        let kinds = day.timelineEvents.map(\.kind)
        #expect(kinds == [.hunger, .food])
    }

    @Test func hungerRecordedLongBeforeAMealIsNotLinkedToIt() {
        // Breakfast's hunger must not be read as lunch's.
        let hungerEntries = [hunger(.veryHungry, nil, at: date(20, 8))]
        let meals = [meal(.regular, at: date(20, 14), density: .light, taste: .tasty)]

        let summary = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: meals,
            hungerEntries: hungerEntries,
            calendar: calendar
        )
        #expect(summary.mealsWithHungerBefore == 0)
        #expect(summary.averageHungerBeforeMeals == nil)
    }

    @Test func hungerRecordedAfterAMealIsNotCountedAsBeforeIt() {
        let hungerEntries = [hunger(.notHungry, nil, at: date(20, 14))]
        let meals = [meal(.regular, at: date(20, 13), density: .filling, taste: .tasty)]

        let summary = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: meals,
            hungerEntries: hungerEntries,
            calendar: calendar
        )
        #expect(summary.mealsWithHungerBefore == 0)
    }

    // MARK: - Backdated entries (spec §Scenario C)

    @Test func aMealRememberedLaterLandsOnTheTimeItHappened() {
        let pasta = meal(.regular, at: date(20, 16, 30), density: .filling, taste: .tasty, desc: "Паста")
        // Written down at 23:00 that evening.
        pasta.createdAt = date(20, 23)

        let day = AnalyticsService.dailySummary(
            date: date(20),
            sessions: [],
            checkIns: [],
            foodEntries: [pasta],
            calendar: calendar
        )
        let event = day.timelineEvents.first { $0.kind == .food }
        #expect(event?.timestamp == date(20, 16, 30))
        #expect(event?.title.contains("Паста") == true)
        #expect(event?.subtitle?.contains("Обычная · Плотно · Вкусно") == true)
    }

    @Test func aMealBelongsToTheDayItHappenedNotTheDayItWasWritten() {
        let lateSnack = meal(.treat, at: date(19, 23, 40), treatType: .salty, treatAmount: .normal)
        lateSnack.createdAt = date(20, 9)

        let dayItHappened = AnalyticsService.foodDaySummary(
            date: date(19),
            foodEntries: [lateSnack],
            hungerEntries: [],
            calendar: calendar
        )
        let dayItWasWritten = AnalyticsService.foodDaySummary(
            date: date(20),
            foodEntries: [lateSnack],
            hungerEntries: [],
            calendar: calendar
        )
        #expect(dayItHappened.mealCount == 1)
        #expect(dayItWasWritten.mealCount == 0)
    }

    // MARK: - Month (spec §16, §Scenario D)

    @Test func theMonthCountsCategoriesAndReportsBothScalesApart() {
        var meals: [FoodEntry] = []
        for day in 1...3 { meals.append(meal(.healthy, at: date(day, 13), density: .filling, taste: .tasty)) }
        for day in 4...5 { meals.append(meal(.regular, at: date(day, 13), density: .light, taste: .tasty)) }
        meals.append(meal(.treat, at: date(6, 20), treatType: .sweet, treatAmount: .little))

        let hungerEntries = [
            hunger(.hungry, .veryHigh, at: date(1, 12)),
            hunger(.wantingToEat, .high, at: date(2, 12))
        ]

        let interval = calendar.dateInterval(of: .month, for: date(1))!
        let summary = AnalyticsService.foodMonthSummary(
            in: interval,
            foodEntries: meals,
            hungerEntries: hungerEntries,
            calendar: calendar
        )

        #expect(summary.mealCount == 6)
        #expect(summary.categoryCounts.first { $0.category == .healthy }?.count == 3)
        #expect(summary.categoryCounts.first { $0.category == .regular }?.count == 2)
        #expect(summary.categoryCounts.first { $0.category == .treat }?.count == 1)
        #expect(summary.treats.byType.first?.type == .sweet)
        #expect(summary.treats.byAmount.first?.amount == .little)
        #expect(summary.averageHunger == 3.5)
        #expect(summary.averageAppetite == 4.5)
        #expect(summary.hungerCount == 2)
        #expect(summary.appetiteCount == 2)
    }

    @Test func aCategoryWithNoEntriesIsAbsentRatherThanZero() {
        let interval = calendar.dateInterval(of: .month, for: date(1))!
        let summary = AnalyticsService.foodMonthSummary(
            in: interval,
            foodEntries: [meal(.healthy, at: date(2, 13), density: .light, taste: .tasty)],
            hungerEntries: [],
            calendar: calendar
        )
        #expect(summary.categoryCounts.count == 1)
        #expect(summary.treats.isEmpty)
    }

    // MARK: - Minimum data (spec §23)

    @Test func aGroupBelowTheSampleThresholdSaysSoAndKeepsItsCount() {
        let entries = (0..<3).map { hunger(.hungry, .high, at: date(2, 8 + $0)) }
        let groups = AnalyticsService.hungerByDayPart(
            hungerEntries: entries,
            foodEntries: [],
            calendar: calendar
        )
        let morning = groups.first { $0.key == DayPart.morning.rawValue }
        #expect(morning?.hungerCount == 3)
        #expect(morning?.hasEnoughData == false)

        let plenty = (0..<6).map { hunger(.hungry, .high, at: date(3, 6 + $0 % 5)) }
        let enough = AnalyticsService.hungerByDayPart(
            hungerEntries: plenty,
            foodEntries: [],
            calendar: calendar
        )
        #expect(enough.first { $0.key == DayPart.morning.rawValue }?.hasEnoughData == true)
    }

    @Test func nightWrapsAroundMidnight() {
        #expect(DayPart.containing(hour: 0) == .night)
        #expect(DayPart.containing(hour: 4) == .night)
        #expect(DayPart.containing(hour: 5) == .morning)
        #expect(DayPart.containing(hour: 23) == .night)
        #expect(DayPart.containing(hour: 12) == .afternoon)
        #expect(DayPart.containing(hour: 17) == .evening)
    }

    // MARK: - Observations around meals (spec §20, §21)

    @Test func moodAndEnergyAreReadFromAfterAMealAndHungerFromBefore() {
        let lunch = meal(.regular, at: date(20, 13), density: .filling, taste: .tasty)
        let before = hunger(.hungry, .high, at: date(20, 12, 30))
        let after = CheckIn(timestamp: date(20, 13, 30), mood: .good, energy: .high, origin: .manual)
        // Well outside the window — must not be counted.
        let muchLater = CheckIn(timestamp: date(20, 18), mood: .veryBad, origin: .manual)

        let observations = AnalyticsService.observationsAroundMeals(
            meals: [lunch],
            checkIns: [after, muchLater],
            hungerEntries: [before]
        )
        let regular = observations.first { $0.category == .regular }
        #expect(regular?.mealCount == 1)
        #expect(regular?.moodSampleCount == 1)
        #expect(regular?.averageMoodAfter == Mood.good.scale)
        #expect(regular?.averageEnergyAfter == EnergyLevel.high.scale)
        #expect(regular?.averageHungerBefore == HungerLevel.hungry.scale)
        // One observation is nowhere near enough to say anything.
        #expect(regular?.hasEnoughMood == false)
    }

    // MARK: - Day screen

    @Test func aDayWithOnlyFoodIsNotAnEmptyDay() {
        let day = AnalyticsService.dailySummary(
            date: date(20),
            sessions: [],
            checkIns: [],
            foodEntries: [meal(.treat, at: date(20, 22), treatType: .sweet, treatAmount: .tooMuch)],
            calendar: calendar
        )
        #expect(!day.isEmpty)
        #expect(day.food.mealCount == 1)
    }

    // MARK: - Export

    @Test func theExportCarriesFoodAndKeepsTheTwoScalesApart() {
        let input = ExportInput(
            foodEntries: [meal(.treat, at: date(7, 20), treatType: .sweet, treatAmount: .little)],
            hungerEntries: [hunger(.veryHungry, .low, at: date(7, 12))]
        )
        let text = DiaryExporter.export(
            input,
            options: ExportOptions(start: date(7), end: date(7), language: .ru),
            calendar: calendar,
            now: date(10, 20)
        )
        #expect(text.contains("Вредная · Сладкое · Чуть-чуть"))
        #expect(text.contains("Голод: 5/5"))
        #expect(text.contains("Аппетит: 2/5"))
    }

    @Test func theExportLeavesOutFoodWhenTheUserExcludedIt() {
        let input = ExportInput(
            foodEntries: [meal(.treat, at: date(7, 20), treatType: .sweet, treatAmount: .little)],
            hungerEntries: [hunger(.veryHungry, .low, at: date(7, 12))]
        )
        var options = ExportOptions(start: date(7), end: date(7), language: .ru)
        options.includeFood = false
        let text = DiaryExporter.export(input, options: options, calendar: calendar, now: date(10, 20))

        #expect(!text.contains("Сладкое"))
        #expect(!text.contains("Голод"))
    }

    @Test func jsonKeepsOnlyTheFieldsBelongingToAMealsCategory() throws {
        let input = ExportInput(
            foodEntries: [meal(.treat, at: date(8, 20), treatType: .sweet, treatAmount: .little)],
            hungerEntries: [hunger(.hungry, nil, at: date(8, 19, 30))]
        )
        let text = DiaryExporter.export(
            input,
            options: ExportOptions(start: date(8), end: date(8), language: .en, format: .json),
            calendar: calendar,
            now: date(10, 20)
        )

        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let food = try #require(object["food"] as? [[String: Any]])
        #expect(food.first?["category"] as? String == "treat")
        #expect(food.first?["treatType"] as? String == "sweet")
        #expect(food.first?["mealDensity"] == nil)
        #expect(food.first?["taste"] == nil)
        // Hunger 30 minutes earlier is inside the window.
        #expect(food.first?["hungerBefore"] as? Int == 4)

        let hungerRecords = try #require(object["hungerAppetite"] as? [[String: Any]])
        #expect(hungerRecords.first?["hunger"] as? Int == 4)
        // Appetite wasn't answered, so it has no number here.
        #expect(hungerRecords.first?["appetite"] == nil)
    }
}
