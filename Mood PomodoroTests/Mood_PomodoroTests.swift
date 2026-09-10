//
//  Mood_PomodoroTests.swift
//  Mood PomodoroTests
//

import Foundation
import Testing
@testable import Mood_Pomodoro

struct Mood_PomodoroTests {

    @Test func elapsedActiveTimeExcludesPauses() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)

        // 20 minutes of wall-clock time, but 5 of those were paused.
        session.accumulatedPauseInterval = 5 * 60
        let asOf = start.addingTimeInterval(20 * 60)

        #expect(session.elapsedActiveTime(asOf: asOf) == 15 * 60)
    }

    @Test func elapsedActiveTimeIncludesOngoingPause() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        session.isPaused = true
        session.pausedAt = start.addingTimeInterval(10 * 60)

        let asOf = start.addingTimeInterval(15 * 60)
        // 10 minutes active before the pause, then 5 minutes paused so far.
        #expect(session.elapsedActiveTime(asOf: asOf) == 10 * 60)
    }

    @Test func scheduleAnchorShiftsByAccumulatedPause() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        session.accumulatedPauseInterval = 90

        #expect(session.scheduleAnchor == start.addingTimeInterval(90))
    }

    @Test func moodActionIdentifierRoundTrips() {
        for mood in Mood.allCases {
            let identifier = NotificationScheduler.actionIdentifier(for: mood)
            #expect(NotificationScheduler.mood(fromActionIdentifier: identifier) == mood)
        }
    }

    // MARK: - Conditions

    @Test func activeConditionsReflectTheMostRecentEventAtOrBeforeTheQueryTime() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        let drinks = FactorCategory(name: "Напиток", icon: "☕")
        let coffee = FactorOption(name: "Кофе", icon: "☕")
        let puerh = FactorOption(name: "Пуэр", icon: "☕")

        let coffeeEvent = ConditionEvent(timestamp: start, category: drinks, option: coffee)
        session.conditionEvents.append(coffeeEvent)
        let puerhEvent = ConditionEvent(timestamp: start.addingTimeInterval(45 * 60), category: drinks, option: puerh)
        session.conditionEvents.append(puerhEvent)

        let beforeSwitch = session.activeConditions(asOf: start.addingTimeInterval(10 * 60))
        #expect(beforeSwitch.first { $0.categoryID == drinks.id }?.optionName == "Кофе")

        let afterSwitch = session.activeConditions(asOf: start.addingTimeInterval(50 * 60))
        #expect(afterSwitch.first { $0.categoryID == drinks.id }?.optionName == "Пуэр")
    }

    @Test func oldCheckInSnapshotIsUnaffectedByALaterConditionChange() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        let drinks = FactorCategory(name: "Напиток", icon: "☕")
        let coffee = FactorOption(name: "Кофе", icon: "☕")
        let puerh = FactorOption(name: "Пуэр", icon: "☕")

        session.conditionEvents.append(ConditionEvent(timestamp: start, category: drinks, option: coffee))

        // Snapshot an early check-in the way SessionManager does: freeze
        // whatever's active right now into the check-in.
        let earlyCheckInTime = start.addingTimeInterval(10 * 60)
        let earlyCheckIn = CheckIn(
            timestamp: earlyCheckInTime,
            mood: .good,
            conditionSnapshot: session.activeConditions(asOf: earlyCheckInTime)
        )

        // The user switches drinks well after that check-in was recorded.
        session.conditionEvents.append(
            ConditionEvent(timestamp: start.addingTimeInterval(45 * 60), category: drinks, option: puerh)
        )

        #expect(earlyCheckIn.conditionSnapshot.first { $0.categoryID == drinks.id }?.optionName == "Кофе")
    }

    // MARK: - AnalyticsService

    @Test func averageMoodIsNilWithNoCheckIns() {
        #expect(AnalyticsService.averageMood(of: []) == nil)
    }

    @Test func averageMoodMatchesTheMoodScale() {
        let checkIns = [CheckIn(mood: .veryGood), CheckIn(mood: .veryBad)]
        #expect(AnalyticsService.averageMood(of: checkIns) == 3.0)
    }

    @Test func moodDistributionCountsEveryMoodIncludingZeros() {
        let checkIns = [CheckIn(mood: .good), CheckIn(mood: .good)]
        let distribution = AnalyticsService.moodDistribution(of: checkIns)
        #expect(distribution.counts[.good] == 2)
        #expect(distribution.counts[.veryBad] == 0)
        #expect(distribution.percentage(for: .good) == 1.0)
    }

    @Test func factorOptionBelowMinimumSampleSizeIsFlaggedAsInsufficientData() {
        let category = FactorCategory(name: "Музыка", icon: "🎧")
        let lofi = FactorOption(name: "Lo-fi", icon: "🎧")
        let checkIns = (0..<(AnalyticsService.minimumSampleSize - 1)).map { _ -> CheckIn in
            let checkIn = CheckIn(mood: .good)
            checkIn.conditionSnapshot = [
                ConditionSnapshotEntry(categoryID: category.id, categoryName: category.name, categoryIcon: category.icon, optionID: lofi.id, optionName: lofi.name)
            ]
            return checkIn
        }
        let stats = AnalyticsService.optionStatistics(category: category, option: lofi, checkIns: checkIns)
        #expect(stats.checkInCount == AnalyticsService.minimumSampleSize - 1)
        #expect(stats.hasEnoughData == false)
    }

    // MARK: - Spec scenario (section 29): 3 sessions, music/drink comparisons, activity filter

    /// Builds the exact dataset from the spec's testing section: two
    /// Programming sessions (one Lo-fi/Pu-erh, one silent/Coffee) and one
    /// Mathematics session (Lo-fi/Coffee), each with its listed mood sequence.
    private struct SpecScenario {
        let music: FactorCategory
        let lofi: FactorOption
        let noMusic: FactorOption
        let drink: FactorCategory
        let puerh: FactorOption
        let coffee: FactorOption
        let sessions: [FocusSession]
    }

    private func makeSpecScenario() -> SpecScenario {
        let music = FactorCategory(name: "Музыка", icon: "🎧")
        let lofi = FactorOption(name: "Lo-fi", icon: "🎧")
        let noMusic = FactorOption(name: "Без музыки", icon: "🎧")
        let drink = FactorCategory(name: "Напиток", icon: "☕")
        let puerh = FactorOption(name: "Пуэр", icon: "☕")
        let coffee = FactorOption(name: "Кофе", icon: "☕")

        for option in [lofi, noMusic] { option.category = music; music.options.append(option) }
        for option in [puerh, coffee] { option.category = drink; drink.options.append(option) }

        func snapshot(_ musicOption: FactorOption, _ drinkOption: FactorOption) -> [ConditionSnapshotEntry] {
            [
                ConditionSnapshotEntry(categoryID: music.id, categoryName: music.name, categoryIcon: music.icon, optionID: musicOption.id, optionName: musicOption.name),
                ConditionSnapshotEntry(categoryID: drink.id, categoryName: drink.name, categoryIcon: drink.icon, optionID: drinkOption.id, optionName: drinkOption.name)
            ]
        }

        func session(activity: String, minutes: Int, moods: [Mood], musicOption: FactorOption, drinkOption: FactorOption) -> FocusSession {
            let start = Date(timeIntervalSince1970: 0)
            let session = FocusSession(activity: activity, startDate: start, checkInIntervalMinutes: minutes / moods.count)
            let step = TimeInterval(minutes * 60) / Double(moods.count)
            for (index, mood) in moods.enumerated() {
                let checkIn = CheckIn(
                    timestamp: start.addingTimeInterval(step * Double(index + 1)),
                    mood: mood,
                    conditionSnapshot: snapshot(musicOption, drinkOption)
                )
                checkIn.session = session
                session.checkIns.append(checkIn)
            }
            return session
        }

        let session1 = session(activity: "Programming", minutes: 60, moods: [.veryGood, .veryGood, .good, .good, .neutral, .tired], musicOption: lofi, drinkOption: puerh)
        let session2 = session(activity: "Programming", minutes: 60, moods: [.good, .neutral, .neutral, .tired, .tired, .veryBad], musicOption: noMusic, drinkOption: coffee)
        let session3 = session(activity: "Mathematics", minutes: 90, moods: [.neutral, .good, .good, .veryGood, .neutral, .tired, .neutral, .veryBad], musicOption: lofi, drinkOption: coffee)

        return SpecScenario(music: music, lofi: lofi, noMusic: noMusic, drink: drink, puerh: puerh, coffee: coffee, sessions: [session1, session2, session3])
    }

    @Test func overallAverageMoodMatchesTheSpecScenario() {
        let scenario = makeSpecScenario()
        // (23 + 15 + 25) / 20 check-ins = 3.15
        #expect(AnalyticsService.averageMood(of: scenario.sessions.flatMap(\.checkIns))! .isApproximately(3.15))
    }

    @Test func musicComparisonMatchesTheSpecScenario() {
        let scenario = makeSpecScenario()
        let result = AnalyticsService.compare(
            optionA: (scenario.music, scenario.lofi),
            optionB: (scenario.music, scenario.noMusic),
            sessions: scenario.sessions
        )
        #expect(result.canCompare)
        #expect(result.optionA.checkInCount == 14) // session 1 + session 3
        #expect(result.optionB.checkInCount == 6)  // session 2
        #expect(result.optionA.averageMood!.isApproximately(48.0 / 14.0))
        #expect(result.optionB.averageMood!.isApproximately(2.5))
        #expect(result.moodDifference! > 0) // Lo-fi sessions averaged higher, observationally
    }

    @Test func drinkComparisonMatchesTheSpecScenario() {
        let scenario = makeSpecScenario()
        let result = AnalyticsService.compare(
            optionA: (scenario.drink, scenario.puerh),
            optionB: (scenario.drink, scenario.coffee),
            sessions: scenario.sessions
        )
        #expect(result.canCompare)
        #expect(result.optionA.checkInCount == 6)  // session 1 only
        #expect(result.optionB.checkInCount == 14) // session 2 + session 3
        #expect(result.optionA.averageMood!.isApproximately(23.0 / 6.0))
        #expect(result.optionB.averageMood!.isApproximately(40.0 / 14.0))
    }

    @Test func activityFilterIsolatesCheckInsToTheChosenActivity() {
        let scenario = makeSpecScenario()
        let programmingCheckIns = AnalyticsService.filteredCheckIns(sessions: scenario.sessions, activity: "Programming")
        let mathCheckIns = AnalyticsService.filteredCheckIns(sessions: scenario.sessions, activity: "Mathematics")
        #expect(programmingCheckIns.count == 12)
        #expect(mathCheckIns.count == 8)
        #expect(AnalyticsService.averageMood(of: programmingCheckIns)!.isApproximately(38.0 / 12.0))
        #expect(AnalyticsService.averageMood(of: mathCheckIns)!.isApproximately(3.125))
    }

    @Test func timeBasedTrajectoryAndFirstDifficultMoodAreComputedFromTheSpecScenario() {
        let scenario = makeSpecScenario()
        let trajectory = AnalyticsService.moodTrajectory(sessions: scenario.sessions, bucketMinutes: 20)
        #expect(!trajectory.isEmpty)

        // Session 1 (60 min, 6 check-ins every 10 min) hits its first difficult
        // mood (🥲) on the 6th check-in, at 60 minutes in.
        let session1 = scenario.sessions[0]
        let firstDifficult = session1.sortedCheckIns.first { $0.mood.isDifficult }
        #expect(firstDifficult?.timestamp.timeIntervalSince(session1.startDate).isApproximately(60 * 60) == true)

        let averageTimeToDifficult = AnalyticsService.averageTimeToFirstDifficultMood(sessions: scenario.sessions)
        #expect(averageTimeToDifficult != nil)
    }

    @Test func factorStatisticsFlagInsufficientSampleWhenAnActivityFilterShrinksAGroupBelowMinimum() {
        let scenario = makeSpecScenario()
        // Пуэр only appears in session 1 (Programming) — filtering to Mathematics
        // leaves zero matching check-ins, which must read as "not enough data",
        // never as "Пуэр works" or "Пуэр doesn't work".
        let stats = AnalyticsService.factorStatistics(categories: [scenario.drink], sessions: scenario.sessions, activity: "Mathematics")
        let puerhStats = stats.first?.optionStats.first { $0.optionName == "Пуэр" }
        #expect(puerhStats?.checkInCount == 0)
        #expect(puerhStats?.hasEnoughData == false)
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.001) -> Bool {
        abs(self - other) < tolerance
    }
}
