//
//  DiaryAnalyticsTests.swift
//  Mood PomodoroTests
//

import Foundation
import Testing
@testable import Mood_Pomodoro

/// Day/month aggregation. Everything here runs on plain objects with a
/// fixed-UTC calendar — no `ModelContainer`, so these can't hit the
/// concurrent-container raciness the main suite works around.
struct DiaryAnalyticsTests {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Deliberately a past year: `SessionSegment.duration(asOf:)` clamps to
    /// "now", so a fixture dated in the future would silently measure zero.
    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour, minute: minute))!
    }

    private func checkIn(_ mood: Mood, at date: Date, session: FocusSession? = nil) -> CheckIn {
        let checkIn = CheckIn(timestamp: date, mood: mood, origin: session == nil ? .manual : .scheduled)
        if let session {
            checkIn.session = session
            session.checkIns = (session.checkIns ?? []) + [checkIn]
        }
        return checkIn
    }

    private func session(activity: String, start: Date, workMinutes: Int) -> FocusSession {
        let session = FocusSession(activity: activity, startDate: start, checkInIntervalMinutes: 10)
        let segment = SessionSegment(
            type: .work,
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(workMinutes * 60))
        )
        segment.session = session
        session.segments = [segment]
        session.endDate = segment.endDate
        session.state = .completed
        return session
    }

    // MARK: - Cycle

    @Test func cycleDayCountsFromTheMostRecentRecordedStart() {
        let entries = [CycleEntry(date: date(1), kind: .periodStart, calendar: calendar)]

        #expect(AnalyticsService.cycleDay(for: date(1), entries: entries, calendar: calendar) == 1)
        #expect(AnalyticsService.cycleDay(for: date(18), entries: entries, calendar: calendar) == 18)
    }

    @Test func cycleDayIsNilBeforeAnythingWasRecorded() {
        let entries = [CycleEntry(date: date(10), kind: .periodStart, calendar: calendar)]
        // The app never back-projects a cycle it wasn't told about.
        #expect(AnalyticsService.cycleDay(for: date(3), entries: entries, calendar: calendar) == nil)
        #expect(AnalyticsService.cycleDay(for: date(1), entries: [], calendar: calendar) == nil)
    }

    @Test func cycleDayRestartsAtTheNextRecordedStart() {
        let entries = [
            CycleEntry(date: date(1), kind: .periodStart, calendar: calendar),
            CycleEntry(date: date(29), kind: .periodStart, calendar: calendar)
        ]
        #expect(AnalyticsService.cycleDay(for: date(28), entries: entries, calendar: calendar) == 28)
        #expect(AnalyticsService.cycleDay(for: date(29), entries: entries, calendar: calendar) == 1)
        #expect(AnalyticsService.cycleDay(for: date(30), entries: entries, calendar: calendar) == 2)
    }

    // MARK: - Day

    @Test func dailySummaryCountsCheckInsByTheirOwnTimestamp() {
        // Session starts 23:40 on the 10th and runs past midnight: its time
        // belongs to the 10th, but the 00:15 check-in belongs to the 11th.
        let start = date(10, 23, 40)
        let lateSession = session(activity: "Математика", start: start, workMinutes: 60)
        let before = checkIn(.good, at: date(10, 23, 50), session: lateSession)
        let after = checkIn(.tired, at: date(11, 0, 15), session: lateSession)

        let tenth = AnalyticsService.dailySummary(
            date: date(10),
            sessions: [lateSession],
            checkIns: [before, after],
            calendar: calendar
        )
        let eleventh = AnalyticsService.dailySummary(
            date: date(11),
            sessions: [lateSession],
            checkIns: [before, after],
            calendar: calendar
        )

        #expect(tenth.moodStats.checkInCount == 1)
        #expect(eleventh.moodStats.checkInCount == 1)
        // Study time is attributed to the day the session started.
        #expect(tenth.totalActiveDuration == 60 * 60)
        #expect(eleventh.activities.isEmpty)
    }

    @Test func dailySummaryIncludesMoodsLoggedWithoutASession() {
        let work = session(activity: "Программирование", start: date(10, 9), workMinutes: 90)
        let scheduled = checkIn(.good, at: date(10, 9, 30), session: work)
        let manual = checkIn(.tired, at: date(10, 21), session: nil)

        let summary = AnalyticsService.dailySummary(
            date: date(10),
            sessions: [work],
            checkIns: [scheduled, manual],
            calendar: calendar
        )

        #expect(summary.moodStats.checkInCount == 2)
        #expect(summary.moodPoints.contains { $0.origin == .manual })
        // The evening mood is on the day's timeline even though no session ran.
        #expect(summary.timelineEvents.contains { $0.timestamp == date(10, 21) })
        // ...but it is never attributed to an activity it wasn't tied to.
        #expect(summary.activities.first?.checkInCount == 1)
    }

    @Test func dailyActivityStatisticsGroupTimeAndMoodPerActivity() {
        let math = session(activity: "Математика", start: date(10, 9), workMinutes: 80)
        let code = session(activity: "Программирование", start: date(10, 13), workMinutes: 105)
        let checkIns = [
            checkIn(.neutral, at: date(10, 9, 20), session: math),
            checkIn(.tired, at: date(10, 10), session: math),
            checkIn(.veryGood, at: date(10, 13, 20), session: code),
            checkIn(.good, at: date(10, 14), session: code)
        ]

        let summary = AnalyticsService.dailySummary(
            date: date(10),
            sessions: [math, code],
            checkIns: checkIns,
            calendar: calendar
        )

        // Sorted by time spent, longest first.
        #expect(summary.activities.map(\.activityName) == ["Программирование", "Математика"])
        #expect(summary.activities[0].activeDuration == 105 * 60)
        #expect(summary.activities[1].activeDuration == 80 * 60)
        #expect(summary.totalActiveDuration == (105 + 80) * 60)
        #expect(summary.activities[0].averageMood == 4.5)
        // Two check-ins is below the sample floor — the UI must not present
        // this as a settled comparison.
        #expect(summary.activities[0].hasEnoughData == false)
    }

    @Test func dailySummaryRecordsTheFirstDifficultMoment() {
        let work = session(activity: "Чтение", start: date(10, 9), workMinutes: 120)
        let checkIns = [
            checkIn(.good, at: date(10, 9, 30), session: work),
            checkIn(.tired, at: date(10, 10, 30), session: work),
            checkIn(.veryBad, at: date(10, 11), session: work)
        ]

        let summary = AnalyticsService.dailySummary(
            date: date(10),
            sessions: [work],
            checkIns: checkIns,
            calendar: calendar
        )

        #expect(summary.moodStats.firstDifficultMoodAt == date(10, 10, 30))
    }

    @Test func emptyDayReportsNothingRatherThanZeroes() {
        let summary = AnalyticsService.dailySummary(
            date: date(10),
            sessions: [],
            checkIns: [],
            calendar: calendar
        )

        #expect(summary.isEmpty)
        #expect(summary.moodStats.average == nil)
        #expect(summary.cycleDay == nil)
    }

    // MARK: - Month

    @Test func monthlySummaryHasOneCellPerDayAndChartsOnlyDaysWithData() {
        let work = session(activity: "Математика", start: date(3, 10), workMinutes: 45)
        let checkIns = [
            checkIn(.good, at: date(3, 10, 20), session: work),
            checkIn(.veryGood, at: date(3, 10, 40), session: work),
            checkIn(.neutral, at: date(17, 15), session: nil)
        ]

        let summary = AnalyticsService.monthlySummary(
            month: date(10),
            sessions: [work],
            checkIns: checkIns,
            calendar: calendar
        )

        #expect(summary.days.count == 30) // September
        #expect(summary.moodOverTime.count == 2) // only the 3rd and the 17th
        #expect(summary.moodStats.checkInCount == 3)
        #expect(summary.days.first { calendar.component(.day, from: $0.date) == 3 }?.averageMood == 4.5)
        #expect(summary.days.first { calendar.component(.day, from: $0.date) == 5 }?.averageMood == nil)
    }

    @Test func monthlySummaryExcludesCheckInsFromOtherMonths() {
        let august = checkIn(.veryGood, at: date(30, 12, month: 8), session: nil)
        let september = checkIn(.tired, at: date(2), session: nil)

        let summary = AnalyticsService.monthlySummary(
            month: date(15),
            sessions: [],
            checkIns: [august, september],
            calendar: calendar
        )

        #expect(summary.moodStats.checkInCount == 1)
        #expect(summary.moodStats.average == 2)
    }

    @Test func cycleBucketsWithholdAnAverageBelowTheSampleFloor() {
        let entries = [CycleEntry(date: date(1), kind: .periodStart, calendar: calendar)]
        // Three check-ins in days 1–5, six in days 6–13.
        var checkIns = (2...4).map { checkIn(.tired, at: date($0), session: nil) }
        checkIns += (6...11).map { checkIn(.good, at: date($0), session: nil) }

        let buckets = AnalyticsService.cycleMoodBuckets(checkIns: checkIns, entries: entries, calendar: calendar)

        let early = buckets.first { $0.dayRange == 1...5 }
        let mid = buckets.first { $0.dayRange == 6...13 }
        #expect(early?.checkInCount == 3)
        #expect(early?.hasEnoughData == false)
        #expect(mid?.checkInCount == 6)
        #expect(mid?.hasEnoughData == true)
        #expect(mid?.averageMood == 4)
    }

    @Test func cycleBucketsAreEmptyWhenNoCycleWasRecorded() {
        let checkIns = (1...10).map { checkIn(.good, at: date($0), session: nil) }
        #expect(AnalyticsService.cycleMoodBuckets(checkIns: checkIns, entries: [], calendar: calendar).isEmpty)
    }

    // MARK: - Backdated entries (event date ≠ created date)

    private func manualSession(activity: String, start: Date, end: Date, createdAt: Date) -> FocusSession {
        let session = FocusSession(activity: activity, startDate: start, checkInIntervalMinutes: 10)
        session.origin = .manual
        session.state = .completed
        session.endDate = end
        session.createdAt = createdAt
        let segment = SessionSegment(type: .work, startDate: start, endDate: end)
        segment.session = session
        session.segments = [segment]
        return session
    }

    @Test func createdAtIsNotTheEventDate() {
        let checkIn = CheckIn(timestamp: date(9, 22, 30), mood: .tired)
        #expect(checkIn.timestamp == date(9, 22, 30))
        #expect(checkIn.createdAt > checkIn.timestamp)
    }

    /// Scenario 1: on the 10th at 20:00, add "9th, 14:00–16:00, programming".
    @Test func backdatedActivityLandsOnTheDayItHappened() {
        let entry = manualSession(
            activity: "Программирование",
            start: date(9, 14),
            end: date(9, 16),
            createdAt: date(10, 20)
        )

        let ninth = AnalyticsService.dailySummary(date: date(9), sessions: [entry], checkIns: [], calendar: calendar)
        let tenth = AnalyticsService.dailySummary(date: date(10), sessions: [entry], checkIns: [], calendar: calendar)
        let month = AnalyticsService.monthlySummary(month: date(9), sessions: [entry], checkIns: [], calendar: calendar)

        #expect(ninth.totalActiveDuration == 2 * 60 * 60)
        #expect(ninth.activities.first?.activityName == "Программирование")
        #expect(tenth.activities.isEmpty)
        #expect(month.totalActiveDuration == 2 * 60 * 60)
        // Its start row sits at 14:00 and opens the edit form.
        let start = ninth.timelineEvents.first { $0.kind == .start }
        #expect(start?.timestamp == date(9, 14))
        #expect(start?.target == .session(entry.id))
    }

    /// Scenario 2: on the 10th, add "8th, 22:30, 🥲" — the 8th's average
    /// and its calendar color both change.
    @Test func backdatedMoodRecolorsItsDay() {
        let morning = checkIn(.good, at: date(8, 10))
        let before = AnalyticsService.monthlySummary(month: date(8), sessions: [], checkIns: [morning], calendar: calendar)

        let late = checkIn(.tired, at: date(8, 22, 30))
        let after = AnalyticsService.monthlySummary(
            month: date(8),
            sessions: [],
            checkIns: [morning, late],
            calendar: calendar
        )

        let eighthBefore = before.days.first { calendar.component(.day, from: $0.date) == 8 }
        let eighthAfter = after.days.first { calendar.component(.day, from: $0.date) == 8 }
        #expect(eighthBefore?.averageMood == 4)
        #expect(eighthAfter?.averageMood == 3)
        #expect(eighthAfter?.checkInCount == 2)
        #expect(MoodColorScale.color(for: 4) != MoodColorScale.color(for: 3))
        // Nothing leaked onto the day it was written.
        #expect(after.days.first { calendar.component(.day, from: $0.date) == 10 }?.averageMood == nil)
    }

    /// Scenario 3: "8th — 💊 принято · 09:15", and unmarked stays unmarked.
    @Test func supportMarkIsShownOnItsDayWithItsTime() {
        let entry = SupportEntry(day: date(8), status: .taken, time: date(8, 9, 15), calendar: calendar)

        let eighth = AnalyticsService.dailySummary(
            date: date(8), sessions: [], checkIns: [], supportEntries: [entry], calendar: calendar
        )
        let seventh = AnalyticsService.dailySummary(
            date: date(7), sessions: [], checkIns: [], supportEntries: [entry], calendar: calendar
        )

        #expect(eighth.support?.status == .taken)
        #expect(eighth.support?.time == date(8, 9, 15))
        #expect(eighth.timelineEvents.contains { $0.kind == .support && $0.timestamp == date(8, 9, 15) })
        // No mark is "не отмечено", never "не принято".
        #expect(seventh.support == nil)
    }

    @Test func supportMarkWithoutATimeStaysOffTheTimeline() {
        let entry = SupportEntry(day: date(8), status: .unknown, calendar: calendar)
        let summary = AnalyticsService.dailySummary(
            date: date(8), sessions: [], checkIns: [], supportEntries: [entry], calendar: calendar
        )
        #expect(summary.support?.status == .unknown)
        #expect(summary.support?.time == nil)
        #expect(!summary.timelineEvents.contains { $0.kind == .support })
    }

    @Test func conflictingSupportMarksResolveToTheLatestEdit() {
        let older = SupportEntry(day: date(8), status: .notTaken, calendar: calendar)
        older.updatedAt = date(8, 10)
        let newer = SupportEntry(day: date(8), status: .taken, calendar: calendar)
        newer.updatedAt = date(9, 10)

        let winner = AnalyticsService.supportEntry(on: date(8), entries: [older, newer], calendar: calendar)
        #expect(winner?.status == .taken)
    }

    @Test func supportMoodStatsLeaveUnmarkedDaysOut() {
        let entries = [
            SupportEntry(day: date(1), status: .taken, calendar: calendar),
            SupportEntry(day: date(2), status: .notTaken, calendar: calendar)
        ]
        let checkIns = [
            checkIn(.good, at: date(1, 10)),
            checkIn(.tired, at: date(2, 10)),
            checkIn(.veryBad, at: date(3, 10)) // unmarked day
        ]
        let stats = AnalyticsService.monthlySummary(
            month: date(1), sessions: [], checkIns: checkIns, supportEntries: entries, calendar: calendar
        ).supportStats

        #expect(stats.map(\.status) == [.taken, .notTaken])
        #expect(stats.first { $0.status == .taken }?.averageMood == 4)
        #expect(stats.reduce(0) { $0 + $1.checkInCount } == 2)
        // One check-in is far below the floor — no average should be shown.
        #expect(stats.allSatisfy { !$0.hasEnoughData })
    }

    /// Scenario 4: on the 10th, mark 7th as the start and 8–10 as continuing.
    @Test func backfilledPeriodCountsCycleDaysFromTheRecordedStart() {
        let entries = [
            CycleEntry(date: date(7), kind: .periodStart, calendar: calendar),
            CycleEntry(date: date(8), kind: .periodDay, calendar: calendar),
            CycleEntry(date: date(9), kind: .periodDay, calendar: calendar),
            CycleEntry(date: date(10), kind: .periodDay, calendar: calendar)
        ]

        for (day, expected) in [(7, 1), (8, 2), (9, 3), (10, 4)] {
            #expect(AnalyticsService.cycleDay(for: date(day), entries: entries, calendar: calendar) == expected)
            #expect(AnalyticsService.isPeriodDay(date(day), entries: entries, calendar: calendar))
        }
        // No end was recorded, so the app doesn't extend the period itself.
        #expect(!AnalyticsService.isPeriodDay(date(11), entries: entries, calendar: calendar))
    }

    @Test func periodCoversTheDaysBetweenARecordedStartAndEnd() {
        let entries = [
            CycleEntry(date: date(7), kind: .periodStart, calendar: calendar),
            CycleEntry(date: date(11), kind: .periodEnd, calendar: calendar)
        ]
        #expect(AnalyticsService.isPeriodDay(date(9), entries: entries, calendar: calendar))
        #expect(AnalyticsService.isPeriodDay(date(11), entries: entries, calendar: calendar))
        #expect(!AnalyticsService.isPeriodDay(date(12), entries: entries, calendar: calendar))
        #expect(!AnalyticsService.isPeriodDay(date(6), entries: entries, calendar: calendar))
    }

    /// Scenario 5: 4.8 / 3.9 → green side, 2.8 → yellow-orange, 1.4 → red,
    /// and an empty day has no color at all.
    @Test func monthColorScaleRunsFromGreenToRed() {
        func isGreen(_ value: Double) -> Bool {
            let (red, green, _) = MoodColorScale.components(for: value)
            return green > red
        }
        #expect(isGreen(4.8))
        #expect(isGreen(3.9))
        #expect(!isGreen(2.8))
        #expect(!isGreen(1.4))

        let (red14, green14, _) = MoodColorScale.components(for: 1.4)
        let (red28, green28, _) = MoodColorScale.components(for: 2.8)
        #expect(red14 - green14 > red28 - green28) // 1.4 is redder than 2.8

        let summary = AnalyticsService.monthlySummary(
            month: date(1),
            sessions: [],
            checkIns: [checkIn(.veryGood, at: date(1, 10))],
            calendar: calendar
        )
        let fifth = summary.days.first { calendar.component(.day, from: $0.date) == 5 }
        #expect(fifth?.hasMoodData == false)
    }

    @Test func diaryNotesAndStandaloneFactorsJoinTheirDay() {
        let note = JournalNote(timestamp: date(9, 18), text: "Гуляла в лесу")
        let category = FactorCategory(name: "Напиток", icon: "☕")
        let option = FactorOption(name: "Пуэр", icon: "🧉")
        let factor = ConditionEvent(timestamp: date(9, 15), category: category, option: option)

        let summary = AnalyticsService.dailySummary(
            date: date(9),
            sessions: [],
            checkIns: [],
            notes: [note],
            diaryFactors: [factor],
            calendar: calendar
        )

        #expect(!summary.isEmpty)
        #expect(summary.conditions.map(\.optionName) == ["Пуэр"])
        #expect(summary.timelineEvents.map(\.target) == [.factor(factor.id), .note(note.id)])
    }
}
