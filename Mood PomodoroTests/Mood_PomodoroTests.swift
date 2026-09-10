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
}
