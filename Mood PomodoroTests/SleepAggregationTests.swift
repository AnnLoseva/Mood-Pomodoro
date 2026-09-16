//
//  SleepAggregationTests.swift
//  Mood PomodoroTests
//

import Foundation
import Testing
@testable import Mood_Pomodoro

/// The sleep rules, tested without HealthKit, a device or a permission
/// prompt — which is the whole reason `SleepAggregationService` is pure.
///
/// What these protect: that a night is never counted twice, that a night and
/// a nap never merge, and that sleep is filed under the day the user woke up.
struct SleepAggregationTests {

    init() {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguage.storageKey)
    }

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour, minute: minute))!
    }

    private func interval(_ stage: SleepStage, _ start: Date, _ end: Date) -> SleepInterval {
        SleepInterval(stage: stage, start: start, end: end)
    }

    private let watch = SleepSourceKey(
        bundleIdentifier: "com.apple.health.watch",
        name: "Anna's Watch",
        productType: "Watch6,1"
    )
    private let phone = SleepSourceKey(
        bundleIdentifier: "com.apple.health.phone",
        name: "Anna's iPhone",
        productType: "iPhone15,2"
    )

    private func hours(_ value: Double) -> TimeInterval { value * 3600 }

    // MARK: - A: a normal Apple Watch night

    @Test func aStagedNightAddsUpToItsStagesAndNoMore() {
        // 23:50 → 08:00, stages back to back, with ten minutes awake in it.
        let intervals = [
            interval(.inBed, date(15, 23, 50), date(16, 8, 0)),
            interval(.core, date(15, 23, 50), date(16, 2, 0)),
            interval(.deep, date(16, 2, 0), date(16, 3, 30)),
            interval(.awake, date(16, 3, 30), date(16, 3, 40)),
            interval(.core, date(16, 3, 40), date(16, 6, 0)),
            interval(.rem, date(16, 6, 0), date(16, 8, 0))
        ]
        let sessions = SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar)
        let night = try! #require(sessions.first)

        #expect(sessions.count == 1)
        // 8h10m in bed, minus the 10 minutes awake = 8h asleep exactly.
        #expect(night.totalSleep == hours(8))
        #expect(night.awake == hours(1.0 / 6))
        // 23:50–02:00 plus 03:40–06:00.
        #expect(night.duration(of: .core) == hours(4.5))
        #expect(night.duration(of: .deep) == hours(1.5))
        #expect(night.duration(of: .rem) == hours(2))
        // In bed is reported apart and is never part of the sleep total.
        #expect(night.timeInBed == hours(8) + hours(1.0 / 6))
        #expect(night.totalSleep < night.timeInBed!)
        #expect(night.kind == .night)
        #expect(night.hasStageDetail)
    }

    // MARK: - B: across midnight

    @Test func aNightIsFiledUnderTheDayTheUserWokeUp() {
        let intervals = [
            interval(.core, date(15, 23, 40), date(16, 4, 0)),
            interval(.rem, date(16, 4, 0), date(16, 8, 20))
        ]
        let night = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        // Slept on the 15th, lived the 16th — the sleep belongs to the 16th.
        #expect(night.day == calendar.startOfDay(for: date(16, 0)))
        #expect(night.start == date(15, 23, 40))
        #expect(night.end == date(16, 8, 20))
    }

    // MARK: - C: a nap is its own session

    @Test func aNightAndAnAfternoonNapStayTwoSessions() {
        let intervals = [
            interval(.core, date(16, 0, 30), date(16, 8, 0)),
            interval(.core, date(16, 15, 20), date(16, 16, 10))
        ]
        let sessions = SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar)

        #expect(sessions.count == 2)
        #expect(sessions[0].kind == .night)
        #expect(sessions[0].totalSleep == hours(7.5))
        #expect(sessions[1].kind == .nap)
        #expect(sessions[1].totalSleep == hours(50.0 / 60))
        // And they are never quietly added into one twelve-hour "sleep".
        #expect(sessions[1].start == date(16, 15, 20))
    }

    @Test func aShortSleepInTheSmallHoursIsStillANight() {
        // Three hours is under the night threshold, but at 02:00 it is not
        // an afternoon nap — it is a short night.
        let intervals = [interval(.core, date(16, 2, 0), date(16, 5, 0))]
        let session = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        #expect(session.kind == .night)
    }

    @Test func aBriefBathroomBreakDoesNotSplitTheNight() {
        // A 25-minute gap with nothing recorded is still one night.
        let intervals = [
            interval(.core, date(16, 0, 0), date(16, 3, 0)),
            interval(.core, date(16, 3, 25), date(16, 8, 0))
        ]
        let sessions = SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar)
        #expect(sessions.count == 1)
        #expect(sessions[0].totalSleep == hours(3) + hours(4.0 + 35.0 / 60))
    }

    // MARK: - D: overlapping inBed must not be added

    @Test func inBedSpanningTheStagesDoesNotInflateTheTotal() {
        // The exact trap from the spec: 9 hours in bed over 8h20m of stages.
        let intervals = [
            interval(.inBed, date(15, 23, 0), date(16, 8, 0)),
            interval(.core, date(15, 23, 30), date(16, 3, 0)),
            interval(.deep, date(16, 3, 0), date(16, 4, 30)),
            interval(.rem, date(16, 4, 30), date(16, 7, 50))
        ]
        let night = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        // Stages only: 3.5 + 1.5 + 3h20m = 8h20m. NOT 9h, and NOT 17h20m.
        #expect(night.totalSleep == hours(8) + hours(1.0 / 3))
        #expect(night.timeInBed == hours(9))
    }

    @Test func stagesThatOverlapEachOtherAreResolvedNotSummed() {
        // A source that writes a coarse "asleep" block *and* detailed stages
        // over the same minutes — adding these would double the night.
        let intervals = [
            interval(.unspecified, date(16, 0, 0), date(16, 6, 0)),
            interval(.core, date(16, 0, 0), date(16, 4, 0)),
            interval(.deep, date(16, 1, 0), date(16, 2, 0))
        ]
        let night = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        #expect(night.totalSleep == hours(6))
        // Deep wins the hour it claims, core keeps the rest of its block,
        // and the coarse block only covers what nothing else did.
        #expect(night.duration(of: .deep) == hours(1))
        #expect(night.duration(of: .core) == hours(3))
        #expect(night.duration(of: .unspecified) == hours(2))
        let total = SleepStage.displayOrder.reduce(0) { $0 + night.duration(of: $1) }
        #expect(total == hours(6))
    }

    @Test func awakeAlwaysWinsTheMinutesItClaims() {
        let intervals = [
            interval(.inBed, date(16, 0, 0), date(16, 8, 0)),
            interval(.core, date(16, 0, 0), date(16, 8, 0)),
            interval(.awake, date(16, 3, 0), date(16, 3, 30))
        ]
        let night = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        #expect(night.totalSleep == hours(7.5))
        #expect(night.awake == hours(0.5))
    }

    @Test func theSameNightGivesTheSameNumbersWhateverTheSampleOrder() {
        let intervals = [
            interval(.core, date(16, 0, 0), date(16, 4, 0)),
            interval(.deep, date(16, 1, 0), date(16, 2, 0)),
            interval(.inBed, date(15, 23, 30), date(16, 4, 30)),
            interval(.rem, date(16, 4, 0), date(16, 6, 0))
        ]
        let forward = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        let backward = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals.reversed()], calendar: calendar).first
        )
        #expect(forward.totalSleep == backward.totalSleep)
        #expect(forward.stageDurations == backward.stageDurations)
        #expect(forward.id == backward.id)
    }

    // MARK: - Several sources

    @Test func twoSourcesForOneNightAreNotAddedTogether() {
        // The phone says "asleep 00:00–07:00"; the watch has the same night
        // in detail. Adding both would report fourteen hours.
        let watchNight = [
            interval(.core, date(16, 0, 0), date(16, 4, 0)),
            interval(.deep, date(16, 4, 0), date(16, 5, 0)),
            interval(.rem, date(16, 5, 0), date(16, 7, 0))
        ]
        let phoneNight = [interval(.unspecified, date(16, 0, 0), date(16, 7, 0))]

        let session = try! #require(
            SleepAggregationService
                .sessions(from: [watch: watchNight, phone: phoneNight], calendar: calendar)
                .first
        )
        #expect(session.totalSleep == hours(7))
        // The staged source wins, so the night keeps its detail.
        #expect(session.sourceBundleIdentifier == watch.bundleIdentifier)
        #expect(session.duration(of: .deep) == hours(1))
    }

    @Test func aSourceWithNoStagesIsStillUsedWhenItIsAllThereIs() {
        let phoneNight = [interval(.unspecified, date(16, 0, 0), date(16, 6, 30))]
        let session = try! #require(
            SleepAggregationService.sessions(from: [phone: phoneNight], calendar: calendar).first
        )
        #expect(session.totalSleep == hours(6.5))
        #expect(!session.hasStageDetail)
        #expect(session.sourceName == "Anna's iPhone")
    }

    // MARK: - E: HealthKit refining a night later

    @Test func aRefinedNightReplacesItsOwnSummaryInsteadOfAddingOne() {
        // Same bounds, more detail than before — the identity must match so
        // the cache updates in place rather than keeping both.
        let coarse = [interval(.unspecified, date(16, 0, 0), date(16, 7, 0))]
        let refined = [
            interval(.core, date(16, 0, 0), date(16, 5, 0)),
            interval(.rem, date(16, 5, 0), date(16, 7, 0))
        ]
        let before = try! #require(
            SleepAggregationService.sessions(from: [watch: coarse], calendar: calendar).first
        )
        let after = try! #require(
            SleepAggregationService.sessions(from: [watch: refined], calendar: calendar).first
        )
        #expect(before.id == after.id)
        #expect(before.totalSleep == after.totalSleep)
        #expect(!before.hasStageDetail)
        #expect(after.hasStageDetail)
    }

    // MARK: - Awakenings

    @Test func awakeningsAreNilWhenNothingWasRecordedRatherThanZero() {
        // A watch may simply not mark the edges of a night, so "no Awake
        // samples" must not be reported as "slept straight through".
        let intervals = [interval(.core, date(16, 0, 0), date(16, 7, 0))]
        let night = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        #expect(night.awakeningCount == nil)
    }

    @Test func onlyAwakeStretchesInsideTheNightCount() {
        let intervals = [
            interval(.core, date(16, 0, 0), date(16, 3, 0)),
            interval(.awake, date(16, 3, 0), date(16, 3, 15)),
            interval(.core, date(16, 3, 15), date(16, 7, 0)),
            // Waking at the very end is the end of the night, not an
            // interruption of it.
            interval(.awake, date(16, 7, 0), date(16, 7, 10))
        ]
        let night = try! #require(
            SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).first
        )
        #expect(night.awakeningCount == 1)
    }

    // MARK: - Noise

    @Test func aFewMinutesOfSleepIsNotReportedAsANap() {
        let intervals = [interval(.core, date(16, 14, 0), date(16, 14, 4))]
        #expect(SleepAggregationService.sessions(from: [watch: intervals], calendar: calendar).isEmpty)
    }

    @Test func noSamplesMeansNoSessionsAndNeverAZero() {
        #expect(SleepAggregationService.sessions(from: [:], calendar: calendar).isEmpty)
        #expect(SleepAggregationService.sessions(from: [watch: []], calendar: calendar).isEmpty)
    }

    // MARK: - Manual entries

    @Test func aManualNightIsOneUndifferentiatedBlock() {
        let summary = try! #require(
            SleepAggregationService.summary(
                of: [interval(.unspecified, date(16, 0, 40), date(16, 7, 50))],
                origin: .manual,
                calendar: calendar
            )
        )
        #expect(summary.source == .manual)
        #expect(summary.totalSleep == hours(7) + hours(1.0 / 6))
        #expect(summary.day == calendar.startOfDay(for: date(16, 0)))
        #expect(!summary.hasStageDetail)
        // A manual entry can never collide with an imported one's identity.
        #expect(summary.id.hasPrefix("manual|"))
    }
}
