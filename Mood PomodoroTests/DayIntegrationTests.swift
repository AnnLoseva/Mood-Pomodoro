import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

@Suite(.serialized)
struct DayIntegrationTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 9, day: day, hour: hour))!
    }
    private func sleep(_ start: Date, _ end: Date, _ source: SleepSource) -> SleepSessionSummary {
        SleepAggregationService.summary(of: [SleepInterval(stage: .unspecified, start: start, end: end)], origin: source, calendar: calendar)!
    }
    @Test func sleepAndFoodAloneStillMakeADayWithoutInventingScales() {
        let meal = FoodEntry(eventDate: date(3, 13), category: .regular)
        let night = sleep(date(2, 23), date(3, 7), .manual)
        let days = AnalyticsService.dayAggregates(foodEntries: [meal], sleepSessions: [night], calendar: calendar)
        #expect(days.count == 1)
        #expect(days[0].mood == nil && days[0].energy == nil && days[0].motivation == nil)
        #expect(days[0].mealCount == 1)
        #expect(days[0].sleepDuration == TimeInterval(8 * 3600))
        let state = AnalyticsService.dayState(
            summary: AnalyticsService.dailySummary(date: date(3), sessions: [], checkIns: [], foodEntries: [meal], calendar: calendar),
            sleep: SleepDaySummary(day: date(3, 0), sessions: [night])
        )
        #expect(!state.hasMood)
        #expect(state.hasSleep)
        #expect(state.mealCount == 1)
    }

    @Test func emptyAndStandaloneDaysNeverInventMood() {
        #expect(AnalyticsService.dayAggregates(calendar: calendar).isEmpty)
        let emotion = EmotionEntry(eventDate: date(3), emotions: [.angry, .sad])
        let impulse = ImpulseEntry(eventDate: date(3), category: .purchase)
        let day = AnalyticsService.dailySummary(date: date(3), sessions: [], checkIns: [], emotionEntries: [emotion], impulseEntries: [impulse], calendar: calendar)
        #expect(!day.isEmpty)
        #expect(day.moodStats.average == nil)
        #expect(day.timelineEvents.count == 2)
        #expect(impulse.strength == nil && impulse.outcome == nil)
        let empty = EmotionEntry(eventDate: date(4), emotions: [])
        #expect(AnalyticsService.dayAggregates(emotionEntries: [empty], calendar: calendar).isEmpty)
    }
    @Test func calendarCanCarryBothMarksWithoutMood() {
        let support = SupportEntry(day: date(3), status: .notTaken, calendar: calendar)
        let cycle = CycleEntry(date: date(3), kind: .periodStart, calendar: calendar)
        let month = AnalyticsService.monthlySummary(month: date(3), sessions: [], checkIns: [], cycleEntries: [cycle], supportEntries: [support], calendar: calendar)
        let marked = month.days.first { calendar.isDate($0.date, inSameDayAs: date(3)) }!
        let empty = month.days.first { calendar.isDate($0.date, inSameDayAs: date(2)) }!
        #expect(marked.supportStatus == .notTaken && marked.isPeriodDay)
        #expect(marked.averageMood == nil)
        #expect(empty.supportStatus == nil && !empty.isPeriodDay)
    }
    @Test func backdatingMovesEventBetweenDays() {
        let entry = EmotionEntry(eventDate: date(3), emotions: [.happy])
        entry.eventDate = date(2)
        let days = AnalyticsService.dayAggregates(emotionEntries: [entry], calendar: calendar)
        #expect(days.count == 1)
        #expect(days[0].day == calendar.startOfDay(for: date(2)))
        #expect(days[0].emotions == [.happy])
    }
    @Test func daysHaveEqualWeightDespiteDifferentObservationCounts() {
        let entries = (0..<20).map { CheckIn(timestamp: date(2).addingTimeInterval(Double($0 * 60)), mood: .veryGood, origin: .manual) }
            + [CheckIn(timestamp: date(3), mood: .veryBad, origin: .manual)]
        let days = AnalyticsService.dayAggregates(checkIns: entries, calendar: calendar)
        let group = AnalyticsService.describe(days: days, key: "all", label: "all")
        let mood = group.scales.first { $0.metric == .mood }!
        #expect(mood.average == 3)
        #expect(mood.dayCount == 2 && mood.observationCount == 21)
        #expect(!mood.hasEnoughData)
    }
    @Test func changedSessionTypeRecalculatesWithoutCreatingRestForPause() {
        let session = FocusSession(activity: "Programming", startDate: date(2), checkInIntervalMinutes: 10)
        let work = SessionSegment(type: .work, startDate: date(2), endDate: date(2).addingTimeInterval(3600))
        let pause = SessionSegment(type: .pause, startDate: date(2).addingTimeInterval(3600), endDate: date(2).addingTimeInterval(4200))
        session.segments = [work, pause]
        session.endDate = pause.endDate
        #expect(session.sessionType == nil)
        session.sessionType = .study
        #expect(AnalyticsService.dayAggregates(sessions: [session], calendar: calendar)[0].duration(of: .study) == 3600)
        session.sessionType = .obligatoryWork
        let day = AnalyticsService.dayAggregates(sessions: [session], calendar: calendar)[0]
        #expect(day.duration(of: .study) == 0 && day.duration(of: .rest) == 0)
        #expect(day.duration(of: .obligatoryWork) == 3600)
        #expect(day.sessionCountsByType[.obligatoryWork] == 1)
    }
    @Test func manualSleepWinsAcrossMidnightInEveryTotal() {
        let imported = sleep(date(2, 23), date(3, 8), .healthKit)
        let manual = sleep(date(2, 22), date(3, 7), .manual)
        let resolved = SleepAggregationService.resolveOverlaps(sessions: [imported, manual])
        #expect(resolved.first { $0.source == .healthKit }!.isSuperseded)
        #expect(manual.day == date(3, 0))
        let summary = SleepDaySummary(day: manual.day, sessions: resolved)
        #expect(summary.totalSleep == 32400.0)
        let interval = calendar.dateInterval(of: .month, for: date(3))!
        #expect(AnalyticsService.sleepStatistics(sessions: resolved, in: interval, calendar: calendar)?.averageSleep == 32400.0)
        #expect(AnalyticsService.dayAggregates(sleepSessions: resolved, calendar: calendar).first?.sleepDuration == 32400.0)
        let restored = SleepAggregationService.resolveOverlaps(sessions: resolved.filter { $0.source == .healthKit })
        #expect(!restored[0].isSuperseded)
    }
    @Test @MainActor func repeatedImportPreservesRatingAndDoesNotDuplicate() throws {
        let container = try ModelContainer(for: SleepRecord.self, HealthCycleDay.self, HealthMedicationDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = SleepStore(container: container)
        let imported = sleep(date(2, 23), date(3, 8), .healthKit)
        store.replaceImported(with: [imported], from: date(1))
        store.setQuality(.good, forSleepID: imported.id)
        store.replaceImported(with: [imported], from: date(1))
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].quality == .good)
        let refined = sleep(date(2, 23).addingTimeInterval(60), date(3, 8), .healthKit)
        store.replaceImported(with: [refined], from: date(1))
        #expect(store.sessions.count == 1 && store.sessions[0].quality == .good)
    }
    @Test func partialMedicationDoesNotBecomeTaken() {
        let record = HealthMedicationDay(day: date(3), takenCount: 1, skippedCount: 1, sourceName: nil, calendar: calendar)
        #expect(record.status == .partial)
        #expect(record.detail != nil)
        let manual = SupportEntry(day: date(3), status: .unknown, calendar: calendar)
        let day = AnalyticsService.dayAggregates(supportEntries: [manual], healthMedication: [date(3, 0): record], calendar: calendar)[0]
        #expect(day.support == .unknown)
    }
    @Test func exportIncludesNewUserRecordsButExcludesImportedSleep() throws {
        let input = ExportInput(emotionEntries: [EmotionEntry(eventDate: date(3), emotions: [.anxious], note: "secret")], impulseEntries: [ImpulseEntry(eventDate: date(3), category: .purchase)], manualSleep: [sleep(date(2, 23), date(3, 8), .healthKit)])
        let options = ExportOptions(start: date(1), end: date(4), language: .en, format: .json, includeNotes: false)
        let text = DiaryExporter.export(input, options: options, calendar: calendar)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((object["emotions"] as? [[String: Any]])?.count == 1)
        #expect((object["impulses"] as? [[String: Any]])?.count == 1)
        #expect((object["manualSleep"] as? [[String: Any]])?.isEmpty == true)
        #expect(!text.contains("secret"))
    }
    @Test @MainActor func oldUntypedRecordsAndNewRecordsSurviveDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diary.store")
        func container() throws -> ModelContainer {
            let schema = Schema([FocusSession.self, CheckIn.self, SessionSegment.self, ConditionEvent.self, FactorCategory.self, FactorOption.self, MoodReason.self, CycleEntry.self, SupportEntry.self, JournalNote.self, FoodEntry.self, HungerEntry.self, EmotionEntry.self, ImpulseEntry.self])
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        }
        let id = UUID()
        do {
            let db = try container()
            let session = FocusSession(id: id, activity: "Legacy title", startDate: date(2), checkInIntervalMinutes: 10)
            db.mainContext.insert(session)
            db.mainContext.insert(EmotionEntry(eventDate: date(3), emotions: [.calm, .happy]))
            try db.mainContext.save()
        }
        let reopened = try container()
        let session = try #require(reopened.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        #expect(session.id == id && session.activity == "Legacy title" && session.sessionType == nil)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<EmotionEntry>()).first?.emotions == [.calm, .happy])
    }
}
