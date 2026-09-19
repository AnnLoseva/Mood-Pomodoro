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
}
