//
//  HealthMergeTests.swift
//  Mood PomodoroTests
//

import Foundation
import Testing
@testable import Mood_Pomodoro

/// Cycle and medication arriving from Apple Health alongside what the user
/// recorded herself.
///
/// The rule these protect: **the user's own entry always wins, Health only
/// fills in the days she didn't mark, and the two are never added together.**
struct HealthMergeTests {

    init() {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguage.storageKey)
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour))!
    }

    private func healthCycle(_ day: Int, flow: MenstrualFlow = .medium, start: Bool = false) -> HealthCycleDay {
        HealthCycleDay(
            day: date(day),
            flow: flow,
            isCycleStart: start,
            sourceName: "Health",
            calendar: calendar
        )
    }

    private func medication(_ day: Int, taken: Int = 0, skipped: Int = 0) -> HealthMedicationDay {
        HealthMedicationDay(
            day: date(day),
            takenCount: taken,
            skippedCount: skipped,
            sourceName: "Health",
            calendar: calendar
        )
    }

    // MARK: - Cycle

    @Test func cycleDayCanBeCountedFromAHealthRecordedStart() {
        // Nothing marked in the app at all — Health carries its own
        // cycle-start flag, which is what makes day 1 knowable.
        let marks = [healthCycle(3, start: true), healthCycle(4), healthCycle(5)].compactMap(\.mark)

        #expect(AnalyticsService.cycleDay(for: date(3), marks: marks, calendar: calendar) == 1)
        #expect(AnalyticsService.cycleDay(for: date(10), marks: marks, calendar: calendar) == 8)
        #expect(AnalyticsService.isPeriodDay(date(4), marks: marks, calendar: calendar))
    }

    @Test func aDayHealthMarksAsNoBleedingIsNotAPeriodDay() {
        // "None" is an answer in Health, and it is not menstruation.
        let marks = [healthCycle(3, flow: .none)].compactMap(\.mark)
        #expect(marks.isEmpty)
        #expect(!AnalyticsService.isPeriodDay(date(3), marks: marks, calendar: calendar))
    }

    @Test func theAppsOwnStartAndHealthsAreCountedTogether() {
        // She marked the September start herself and Health has the October
        // one. Cycle day must follow whichever start is most recent.
        let own = CycleEntry(date: date(1), kind: .periodStart, calendar: calendar)
        let health = healthCycle(29, start: true)
        let marks = [own.mark] + [health].compactMap(\.mark)

        #expect(AnalyticsService.cycleDay(for: date(28), marks: marks, calendar: calendar) == 28)
        #expect(AnalyticsService.cycleDay(for: date(29), marks: marks, calendar: calendar) == 1)
        #expect(AnalyticsService.cycleDay(for: date(30), marks: marks, calendar: calendar) == 2)
    }

    @Test func theSameDayFromBothSourcesIsStillOneDay() {
        // Both the app and Health know about the 3rd. Counting must not
        // double it or shift anything.
        let own = CycleEntry(date: date(3), kind: .periodStart, calendar: calendar)
        let marks = [own.mark] + [healthCycle(3, start: true)].compactMap(\.mark)

        #expect(AnalyticsService.cycleDay(for: date(3), marks: marks, calendar: calendar) == 1)
        #expect(AnalyticsService.cycleDay(for: date(7), marks: marks, calendar: calendar) == 5)
    }

    @Test func aHealthCycleDayFlowsIntoTheDaysSummary() {
        let summary = AnalyticsService.dailySummary(
            date: date(4),
            sessions: [],
            checkIns: [],
            healthCycleMarks: [healthCycle(3, start: true), healthCycle(4)].compactMap(\.mark),
            calendar: calendar
        )
        #expect(summary.cycleDay == 2)
        #expect(summary.isPeriodDay)
    }

    // MARK: - Medication

    @Test func aDayWithNothingLoggedInHealthSaysNothing() {
        // Untouched reminders are not skips — such a day has no status and
        // must stay "не отмечено".
        #expect(medication(5).status == nil)
    }

    @Test func healthMedicationAnswersOnlyTheDaysTheUserDidNotMark() {
        let summary = AnalyticsService.dailySummary(
            date: date(5),
            sessions: [],
            checkIns: [],
            healthMedication: medication(5, taken: 1),
            calendar: calendar
        )
        let support = try! #require(summary.support)
        #expect(support.status == .taken)
        #expect(support.source == .healthKit)
    }

    @Test func herOwnMarkAlwaysWinsOverHealth() {
        // She wrote "не помню" in the app; Health thinks a dose was taken.
        // Her own answer is the one the diary shows.
        let own = SupportEntry(day: date(5), status: .unknown, calendar: calendar)
        let summary = AnalyticsService.dailySummary(
            date: date(5),
            sessions: [],
            checkIns: [],
            supportEntries: [own],
            healthMedication: medication(5, taken: 1),
            calendar: calendar
        )
        let support = try! #require(summary.support)
        #expect(support.status == .unknown)
        #expect(support.source == .manual)
    }

    @Test func aDayWhereEverythingWasSkippedReadsAsNotTaken() {
        #expect(medication(5, skipped: 2).status == .notTaken)
        // Mixed days read as taken: one dose really was taken.
        #expect(medication(5, taken: 1, skipped: 1).status == .taken)
    }

    @Test func monthlySupportStatisticsCountHealthDaysToo() {
        let checkIns = (0..<6).map { CheckIn(timestamp: date(5, 9 + $0), mood: .good, origin: .manual) }
        let interval = calendar.dateInterval(of: .month, for: date(1))!

        let stats = AnalyticsService.supportMoodStatistics(
            checkIns: checkIns,
            supportEntries: [],
            healthMedication: [calendar.startOfDay(for: date(5)): medication(5, taken: 1)],
            in: interval,
            calendar: calendar
        )
        let taken = try! #require(stats.first { $0.status == .taken })
        #expect(taken.dayCount == 1)
        #expect(taken.checkInCount == 6)
    }

    @Test func herOwnMarkAlsoWinsInTheMonthlyFigures() {
        // One day, two sources disagreeing. It must count once, as hers.
        let own = SupportEntry(day: date(5), status: .notTaken, calendar: calendar)
        let interval = calendar.dateInterval(of: .month, for: date(1))!

        let stats = AnalyticsService.supportMoodStatistics(
            checkIns: [],
            supportEntries: [own],
            healthMedication: [calendar.startOfDay(for: date(5)): medication(5, taken: 1)],
            in: interval,
            calendar: calendar
        )
        #expect(stats.count == 1)
        #expect(stats.first?.status == .notTaken)
        #expect(stats.first?.dayCount == 1)
    }
}
