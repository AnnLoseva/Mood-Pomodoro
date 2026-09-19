import Foundation
import Testing
@testable import Mood_Pomodoro

@Suite
struct TimelineLineTests {
    init() {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguage.storageKey)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2024, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func point(_ at: Date, _ value: Double) -> TimelineMark {
        TimelineMark(
            id: "p-\(at.timeIntervalSince1970)",
            date: at,
            layer: .mood,
            value: value,
            caption: .scale(layer: .mood, value: Int(value))
        )
    }

    @Test func aQuietStretchNeverBreaksALine() {
        let points = [point(date(2, 9), 4), point(date(2, 15), 3), point(date(9, 10), 2)]
        #expect(TimelineSnapshotBuilder.numericGroups(points).count == 1)
    }

    @Test func aNightsSleepBreaksTheLineAndNothingElseDoes() {
        let night = DateInterval(start: date(2, 23), end: date(3, 7))
        let points = [point(date(2, 9), 4), point(date(2, 21), 3), point(date(3, 8), 4), point(date(3, 18), 2)]
        let groups = TimelineSnapshotBuilder.numericGroups(points, breakingAt: [night])
        #expect(groups.map(\.count) == [2, 2])
    }

    @Test func dayAverageIsWeightedByHoursNotByCheckIns() {
        // Three check-ins within the first hour at 5, then one at 1 twelve
        // hours later: by count the mean would be 4, by hours it sits
        // near the middle.
        let points = [
            point(date(2, 0, 0), 5), point(date(2, 0, 20), 5), point(date(2, 0, 40), 5), point(date(2, 12, 0), 1)
        ]
        let averages = TimelineSnapshotBuilder.dailyAverages(points, layer: .mood, calendar: utc)
        #expect(averages.count == 1)
        let value = averages[0].value ?? 0
        #expect(value < 3.5)
        #expect(value > 2.5)
    }

    @Test func daysWithoutRecordsGetNoPointButTheLineRunsThrough() {
        let points = [point(date(2, 12), 2), point(date(5, 12), 5)]
        let averages = TimelineSnapshotBuilder.dailyAverages(points, layer: .mood, calendar: utc)
        #expect(averages.count == 2)
        #expect(TimelineSnapshotBuilder.numericGroups(averages).count == 1)
    }

    @Test func aLoneRecordIsItsOwnDayAverage() {
        let averages = TimelineSnapshotBuilder.dailyAverages([point(date(4, 10), 3)], layer: .mood, calendar: utc)
        #expect(averages.count == 1)
        #expect(averages[0].value == 3)
    }

    private func sleep(_ id: String, _ kind: SleepKind, day: Int, hours: Double) -> SleepSessionSummary {
        let start = date(day, 1)
        return SleepSessionSummary(
            id: id, day: date(day, 0), kind: kind, source: .manual,
            start: start, end: start.addingTimeInterval(hours * 3600),
            totalSleep: hours * 3600, timeInBed: nil, awake: 0, stageDurations: [:],
            awakeningCount: nil, intervals: [], sourceName: nil, sourceBundleIdentifier: nil, productType: nil
        )
    }

    @Test func sleepLineAddsNightAndNapOfTheSameDay() {
        let interval = DateInterval(start: date(1, 0), end: date(8, 0))
        let days = TimelineSnapshotBuilder.sleepDays([
            sleep("a", .night, day: 3, hours: 6),
            sleep("b", .nap, day: 3, hours: 1.5),
            sleep("c", .night, day: 5, hours: 8),
            sleep("outside", .night, day: 9, hours: 8)
        ], in: interval, calendar: utc)
        #expect(days.map(\.value) == [7.5, 8])
    }

    // MARK: - Paging between periods

    @Test func monthsFollowOneAnotherThroughTheYearEnd() {
        var days: [Int] = []
        var month = utc.date(from: DateComponents(year: 2024, month: 11, day: 15))!
        for _ in 0..<4 {
            days.append(AnalyticsService.monthlySummary(month: month, sessions: [], checkIns: [], calendar: utc).days.count)
            month = utc.date(byAdding: .month, value: 1, to: month)!
        }
        // November, December, January, February (2025, not a leap year).
        #expect(days == [30, 31, 31, 28])
    }

    @Test func aPeriodSummaryCoversEveryDayOfItsInterval() {
        let interval = DateInterval(start: date(1, 0), end: date(1, 0).addingTimeInterval(40 * 86400))
        let summary = AnalyticsService.periodSummary(in: interval, sessions: [], checkIns: [], calendar: utc)
        #expect(summary.days.count == 40)
    }

    @Test func allTimeReadsFromTheBeginningToTheEndOfToday() {
        let interval = DiaryPeriodInterval.visible(for: .now, span: .all, calendar: utc)
        #expect(interval.start == .distantPast)
        #expect(interval.end > .now)
        #expect(interval.end.timeIntervalSince(.now) <= 86400)
        #expect(TimelineSpan.all.calendarComponent == nil)
    }
}
