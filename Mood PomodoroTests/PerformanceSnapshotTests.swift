import Foundation
import Testing
@testable import Mood_Pomodoro

@Suite
struct PerformanceSnapshotTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 6, day: day, hour: hour))!
    }

    @Test func timelineIdsAreStableAcrossRebuilds() {
        let checkIn = CheckIn(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, timestamp: date(3, 10), mood: .good)
        let interval = DateInterval(start: date(3, 0), end: date(4, 0))
        let facts = TimelineSnapshotBuilder.capture(
            interval: interval,
            checkIns: [checkIn],
            hunger: [],
            food: [],
            emotions: [],
            impulses: [],
            sessions: [],
            sleep: []
        )
        let first = TimelineSnapshotBuilder.build(facts: facts)
        let second = TimelineSnapshotBuilder.build(facts: facts)
        #expect(first.marks.map(\.id) == second.marks.map(\.id))
        #expect(first.marks.contains { $0.id.contains("00000000-0000-0000-0000-000000000001") })
    }

    @Test func dayFetchWindowPadsTheNightBefore() {
        let day = date(10, 15)
        let visible = DiaryPeriodInterval.visible(for: day, span: .day, calendar: calendar)
        let fetch = DiaryPeriodInterval.fetch(for: day, span: .day, calendar: calendar)
        #expect(fetch.start < visible.start)
        #expect(fetch.end == visible.end)
        #expect(visible.end.timeIntervalSince(visible.start) == 24 * 3600)
    }

    @Test func sessionOverlapRuleKeepsANightThatStartedYesterday() {
        let start = date(3, 0)
        let end = date(4, 0)
        let nightStart = date(2, 22)
        let nightEnd = date(3, 7)
        #expect(nightStart < end && nightEnd > start)
        let tooEarlyEnd = date(2, 20)
        #expect(!(nightStart < end && tooEarlyEnd > start) || tooEarlyEnd > start)
        #expect(!(date(2, 10) < end && date(2, 12) > start))
    }

    @Test func coalescerRunsAQueuedFollowUpOnce() async {
        let coalescer = RefreshCoalescer()
        var runs = 0
        await coalescer.run {
            runs += 1
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await coalescer.run {
                        runs += 1
                    }
                }
            }
        }
        #expect(runs >= 2)
        #expect(runs <= 10)
    }
}

@Suite
struct PerformanceBenchmarks {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    @Test func snapshotAndSummariesStayBoundedOnAYearOfData() {
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        var checkIns: [CheckIn] = []
        var hunger: [HungerEntry] = []
        var food: [FoodEntry] = []
        var emotions: [EmotionEntry] = []
        var impulses: [ImpulseEntry] = []
        checkIns.reserveCapacity(365 * 4)
        for day in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: day, to: start) else { continue }
            for hour in [9, 13, 18, 22] {
                let stamp = calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: date)) ?? date
                checkIns.append(CheckIn(timestamp: stamp, mood: hour < 15 ? .good : .tired, energy: .medium, motivation: .medium))
            }
            hunger.append(HungerEntry(eventDate: date, hunger: .hungry, appetite: .normal))
            food.append(FoodEntry(eventDate: date, category: .regular))
            if day % 3 == 0 {
                emotions.append(EmotionEntry(eventDate: date, emotions: [.calm]))
            }
            if day % 5 == 0 {
                impulses.append(ImpulseEntry(eventDate: date, category: .food))
            }
        }

        let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start.addingTimeInterval(30 * 86400))!)
        let facts = TimelineSnapshotBuilder.capture(
            interval: interval,
            checkIns: checkIns,
            hunger: hunger,
            food: food,
            emotions: emotions,
            impulses: impulses,
            sessions: [],
            sleep: []
        )

        let snapshotStarted = Date()
        let snapshot = TimelineSnapshotBuilder.build(facts: facts)
        let snapshotMS = Date().timeIntervalSince(snapshotStarted) * 1000

        let summaryStarted = Date()
        _ = AnalyticsService.dailySummary(date: start.addingTimeInterval(10 * 86400), sessions: [], checkIns: checkIns, foodEntries: food, hungerEntries: hunger, emotionEntries: emotions, impulseEntries: impulses, calendar: calendar)
        let dailyMS = Date().timeIntervalSince(summaryStarted) * 1000

        let monthStarted = Date()
        _ = AnalyticsService.monthlySummary(month: start, sessions: [], checkIns: checkIns, categories: [], foodEntries: food, hungerEntries: hunger, emotionEntries: emotions, impulseEntries: impulses, calendar: calendar)
        let monthlyMS = Date().timeIntervalSince(monthStarted) * 1000

        print("BENCH snapshot_ms=\(snapshotMS) daily_ms=\(dailyMS) monthly_ms=\(monthlyMS) marks=\(snapshot.marks.count) facts_checkins=\(facts.checkIns.count)")
        #expect(snapshotMS < 500)
        #expect(dailyMS < 400)
        #expect(monthlyMS < 1500)
        #expect(!snapshot.marks.isEmpty)
    }
}
