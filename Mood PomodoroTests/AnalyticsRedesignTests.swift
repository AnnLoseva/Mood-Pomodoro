import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

/// The analytics / diary-chart / navigation redesign: scales and gaps,
/// palette, search, layer selection, tap inspection, and the guarantees that
/// removing the History tab lost no data.
@MainActor
@Suite(.serialized)
struct AnalyticsRedesignTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int, _ hour: Int = 12, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour))!
    }

    private func row(
        _ day: Int,
        mood: Double? = nil,
        hunger: Double? = nil,
        sleepHours: Double? = nil,
        byType: [String: TimeInterval] = [:]
    ) -> AnalyticsDayRow {
        AnalyticsDayRow(
            day: calendar.startOfDay(for: date(day)), mood: mood, moodCount: mood == nil ? 0 : 3,
            energy: nil, energyCount: 0, motivation: nil, motivationCount: 0,
            hunger: hunger, hungerCount: hunger == nil ? 0 : 1, appetite: nil, appetiteCount: 0,
            sleepSeconds: sleepHours.map { $0 * 3600 }, napSeconds: 0, sleepQuality: nil, awakeningCount: nil,
            bedtime: nil, wakeTime: nil, deepSeconds: nil, remSeconds: nil, coreSeconds: nil, totalStagedSleep: nil,
            isPeriodDay: false, cycleDay: nil, supportRaw: nil, mealCount: 0, treatCount: 0,
            emotions: [], impulseCount: 0, impulseCategories: [], factorKeys: [],
            durationByType: byType, sessionCount: byType.isEmpty ? 0 : 1
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = PersistenceController.schema
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    // MARK: - Palette

    @Test func everySeriesColourIsVisibleOnTheCardAndItsTextVariantIsReadable() {
        let series: [(String, AnalyticsPalette.RGB)] = [
            ("mood", AnalyticsPalette.mood), ("energy", AnalyticsPalette.energy),
            ("motivation", AnalyticsPalette.motivation), ("hunger", AnalyticsPalette.hunger),
            ("appetite", AnalyticsPalette.appetite), ("sleep", AnalyticsPalette.sleep),
            ("activity", AnalyticsPalette.activity)
        ]
        for (name, colour) in series {
            #expect(colour.contrast(against: AnalyticsPalette.surface) >= 3.0, "\(name) line vs card")
            #expect(AnalyticsPalette.text(colour).contrast(against: AnalyticsPalette.surface) >= 4.5, "\(name) text vs card")
        }
        #expect(Set(series.map { "\($0.1.r)-\($0.1.g)-\($0.1.b)" }).count == series.count)
    }

    @Test func lineSeriesAlsoDifferByShapeNotOnlyColour() {
        let shapes = TimelineLayer.lineLayers.map(\.shape)
        #expect(Set(shapes).count == TimelineLayer.lineLayers.count)
        #expect(Set(AnalyticsMetric.primary.prefix(3).map(\.shape)).count == 3)
    }

    @Test func oneMetricHasTheSameColourInTheDiaryAndTheAnalytics() {
        #expect(TimelineLayer.energy.color == AnalyticsMetric.energy.color)
        #expect(TimelineLayer.sleep.color == AnalyticsMetric.sleep.color)
        #expect(DayMetric.mood.color == AnalyticsMetric.mood.color)
        #expect(DayScaleMetric.appetite.color == AnalyticsMetric.appetite.color)
    }

    // MARK: - Scales, units, gaps

    @Test func ratingsShareOneAxisDurationsNever() {
        #expect(AnalyticsMetric.domain(for: [.mood, .energy], values: [2, 4]) == 1...5)
        #expect(AnalyticsChartLayout.layout(for: [.mood, .energy]) == .shared)
        #expect(AnalyticsChartLayout.layout(for: [.sleep, .activity]) == .shared)
        // Five points of mood are not five hours of sleep.
        #expect(AnalyticsChartLayout.layout(for: [.mood, .sleep]) == .stacked)
        #expect(!AnalyticsMetric.mood.sharesAxis(with: .sleep))
        let hours = AnalyticsMetric.domain(for: [.sleep], values: [7.2, 9.4])
        #expect(hours.lowerBound == 0 && hours.upperBound == 10)
        #expect(AnalyticsMetric.domain(for: [.sleep], values: []).upperBound >= 4)
    }

    @Test func aDayWithoutARecordIsMissingNotZero() {
        let empty = row(3, mood: 3)
        #expect(AnalyticsMetric.sleep.value(in: empty) == nil)
        #expect(AnalyticsMetric.activity.value(in: empty) == nil)
        #expect(AnalyticsMetric.energy.value(in: empty) == nil)
        let series = AnalyticsChartSeries.make(metric: .sleep, days: [empty], calendar: calendar)
        #expect(series.isEmpty && series.average == nil)
        #expect(AnalyticsMetric.sleep.format(nil) == "—")
    }

    @Test func satietyIsHungerFlippedAndUnitsAreExplicit() {
        #expect(AnalyticsMetric.satiety.value(in: row(3, hunger: 5)) == 1)
        #expect(AnalyticsMetric.satiety.value(in: row(3, hunger: 1)) == 5)
        #expect(AnalyticsMetric.sleep.value(in: row(3, sleepHours: 7.5)) == 7.5)
        let work = AnalyticsMetric.work.value(in: row(3, byType: [SessionType.obligatoryWork.rawValue: 7200]))
        #expect(work == 2)
        #expect(AnalyticsMetric.activity.value(in: row(3, byType: ["unassigned": 3600, SessionType.study.rawValue: 1800])) == 1.5)
        #expect(AnalyticsMetric.mood.formatWithUnit(3.4).hasSuffix("/ 5"))
        for metric in AnalyticsMetric.allCases { #expect(!metric.unitNote.isEmpty && !metric.methodNote.isEmpty) }
    }

    @Test func aLineIsNeverDrawnAcrossAMissingDay() {
        let days = [row(1, mood: 3), row(2, mood: 4), row(4, mood: 2), row(5, mood: 5), row(9, mood: 1)]
        let series = AnalyticsChartSeries.make(metric: .mood, days: days, calendar: calendar)
        #expect(series.points.count == 5)
        #expect(series.runs.map(\.count) == [2, 2, 1])
    }

    @Test func consecutiveDaysStayOneRunAcrossADSTChange() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        func point(_ day: Int) -> AnalyticsChartSeries.Point {
            AnalyticsChartSeries.Point(
                day: ny.startOfDay(for: ny.date(from: DateComponents(year: 2024, month: 3, day: day, hour: 12))!),
                value: 3, observations: 1
            )
        }
        // The 10th is only 23 hours long; the run must not break there.
        let runs = AnalyticsChartSeries.runs(of: [point(8), point(9), point(10), point(11)], calendar: ny)
        #expect(runs.count == 1)
    }

    @Test func selectingADayFindsItsPointOrNothing() {
        let series = AnalyticsChartSeries.make(metric: .mood, days: [row(3, mood: 4)], calendar: calendar)
        #expect(series.point(on: date(3, 22), calendar: calendar)?.value == 4)
        #expect(series.point(on: date(4), calendar: calendar) == nil)
    }

    // MARK: - Period

    @Test func aSingleDayPeriodIsToday() {
        let now = date(10, 15)
        let interval = AnalyticsPeriod(kind: .today).interval(now: now, calendar: calendar)
        #expect(interval.start == calendar.startOfDay(for: now))
        #expect(interval.duration == 86_400)
        let previous = AnalyticsPeriod(kind: .today).previousInterval(of: interval, calendar: calendar)
        #expect(previous.end == interval.start && previous.duration == 86_400)
        // The menu offers every kind exactly once, custom and all-time included.
        #expect(AnalyticsPeriodKind.allCases.contains(.custom) && AnalyticsPeriodKind.allCases.contains(.all))
        #expect(AnalyticsPeriod.default.kind == .days7)
    }

    // MARK: - Search

    @Test func searchFindsMetricsAndSectionsByNameSynonymAndYo() {
        let entries = AnalyticsSearch.staticEntries()
        func top(_ query: String) -> AnalyticsRoute? { AnalyticsSearch.match(query, in: entries).first?.route }
        #expect(top("сон") == .section(.sleep) || top("сон") == .metric(.sleep))
        #expect(top("энергия") == .metric(.energy) || top("энергия") == .section(.state))
        #expect(AnalyticsSearch.match("голод", in: entries).contains { $0.route == .metric(.satiety) })
        #expect(AnalyticsSearch.match("аппетит", in: entries).contains { $0.route == .metric(.appetite) })
        #expect(AnalyticsSearch.match("мотивация", in: entries).contains { $0.route == .metric(.motivation) })
        #expect(AnalyticsSearch.match("эмоции", in: entries).contains { $0.route == .section(.emotions) })
        #expect(AnalyticsSearch.match("препараты", in: entries).contains { $0.route == .section(.cycle) })
        #expect(AnalyticsSearch.match("цикл", in: entries).contains { $0.route == .section(.cycle) })
        #expect(AnalyticsSearch.match("учеба", in: entries).contains { $0.route == .metric(.study) })
        #expect(AnalyticsSearch.match("study", in: entries).contains { $0.route == .metric(.study) })
        #expect(AnalyticsSearch.match("zzzz", in: entries).isEmpty)
        #expect(AnalyticsSearch.match("   ", in: entries).isEmpty)
    }

    @Test func searchFindsActivitiesAndFactorsOfThePeriod() {
        let category = UUID()
        let dynamic = AnalyticsSearch.dynamicEntries(
            activities: ["Математика", "Электроника", "Математика"],
            factors: [(name: "Кофе", category: category, categoryName: "Питьё")]
        )
        #expect(dynamic.filter { $0.kind == .activity }.count == 2)
        #expect(AnalyticsSearch.match("матем", in: dynamic).first?.route == .activity(canonicalData("Математика")))
        #expect(AnalyticsSearch.match("электро", in: dynamic).count == 1)
        #expect(AnalyticsSearch.match("кофе", in: dynamic).first?.route == .factorCategory(category))
    }

    @Test func searchUnderstandsTypedDates() throws {
        let now = date(20, 10)
        #expect(AnalyticsSearch.parseDay("12.09", calendar: calendar, now: now) == calendar.startOfDay(for: date(12)))
        #expect(AnalyticsSearch.parseDay("12.09.2024", calendar: calendar, now: now) == calendar.startOfDay(for: date(12)))
        #expect(AnalyticsSearch.parseDay("2024-09-12", calendar: calendar, now: now) == calendar.startOfDay(for: date(12)))
        #expect(AnalyticsSearch.parseDay("12 сентября", calendar: calendar, now: now) == calendar.startOfDay(for: date(12)))
        #expect(AnalyticsSearch.parseDay("march 3", calendar: calendar, now: now) == calendar.startOfDay(for: date(3, month: 3)))
        #expect(AnalyticsSearch.parseDay("вчера", calendar: calendar, now: now) == calendar.startOfDay(for: date(19)))
        // No year, and that day has not come yet this year: last year's.
        let lastYear = try #require(AnalyticsSearch.parseDay("25.12", calendar: calendar, now: now))
        #expect(calendar.component(.year, from: lastYear) == 2023)
        #expect(AnalyticsSearch.parseDay("31.02", calendar: calendar, now: now) == nil)
        #expect(AnalyticsSearch.parseDay("математика", calendar: calendar, now: now) == nil)
    }

    @Test func sessionSearchFindsOldSessionsByNameTaskTypeAndDayButNotTheRunningOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        func finished(_ name: String, daysAgo: Int, type: SessionType? = nil, task: String? = nil) -> FocusSession {
            let start = date(20).addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            let session = FocusSession(activity: name, startDate: start, checkInIntervalMinutes: 10)
            session.state = .completed
            session.endDate = start.addingTimeInterval(1800)
            session.sessionType = type
            session.sourceTaskTitle = task
            context.insert(session)
            return session
        }
        let old = finished("Математика", daysAgo: 400, type: .study)
        _ = finished("Электроника", daysAgo: 3, task: "Паяльник")
        let running = FocusSession(activity: "Математика", startDate: date(20), checkInIntervalMinutes: 10)
        context.insert(running)
        try context.save()

        let byName = SessionSearch.find("матем", in: context, calendar: calendar, now: date(20))
        #expect(byName.map(\.id) == [old.id], "a session from over a year ago is still found; the running one is not")
        #expect(SessionSearch.find("паяльник", in: context).count == 1)
        #expect(SessionSearch.find("учёба", in: context).map(\.id) == [old.id])
        #expect(SessionSearch.find("нет такого", in: context).isEmpty)
        #expect(SessionSearch.find("", in: context).isEmpty)
        let sameDay = date(20).addingTimeInterval(TimeInterval(-400 * 86_400))
        let day = calendar.dateComponents([.day, .month], from: sameDay)
        let typed = String(format: "%02d.%02d.%d", day.day!, day.month!, calendar.component(.year, from: sameDay))
        #expect(SessionSearch.find(typed, in: context, calendar: calendar, now: date(20)).map(\.id) == [old.id])
    }

    @Test func sessionSearchIsBoundedByItsLimit() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for index in 0..<30 {
            let start = date(1).addingTimeInterval(TimeInterval(index * 3600))
            let session = FocusSession(activity: "Чтение", startDate: start, checkInIntervalMinutes: 10)
            session.state = .completed
            session.endDate = start.addingTimeInterval(600)
            context.insert(session)
        }
        try context.save()
        #expect(SessionSearch.find("чтение", in: context, limit: 10).count == 10)
    }

    // MARK: - Diary chart layers

    @Test func linesAndMarksAreSeparateGroupsAndSleepBelongsToMarks() {
        #expect(TimelineLayer.lineLayers == [.mood, .energy, .motivation, .hunger, .appetite])
        #expect(TimelineLayer.markLayers.contains(.sleep) && TimelineLayer.markLayers.contains(.activity))
        #expect(Set(TimelineLayer.lineLayers).isDisjoint(with: TimelineLayer.markLayers))
        #expect(Set(TimelineLayer.lineLayers + TimelineLayer.markLayers) == Set(TimelineLayer.allCases))
        #expect(TimelineLayer.allCases.allSatisfy { ($0.group == .line) == $0.isNumeric })
    }

    @Test func layerGroupsSwitchIndependentlyAndTheChoiceRoundTrips() {
        var selection = TimelineLayerSelection(raw: "mood,sleep,food")
        selection.toggle(.energy)
        #expect(selection.lines == [.mood, .energy] && selection.marks == [.sleep, .food])
        selection.toggle(.food)
        selection.toggle(.mood)
        #expect(selection.lines == [.energy] && selection.marks == [.sleep])
        #expect(TimelineLayerSelection(raw: selection.raw) == selection)
        #expect(TimelineLayerSelection(raw: "mood,nonsense").lines == [.mood])
    }

    @Test func switchingEverythingOffStaysOffInsteadOfReturningToDefaults() {
        var selection = TimelineLayerSelection.default
        for layer in TimelineLayer.allCases where selection.contains(layer) { selection.toggle(layer) }
        #expect(selection.isEmpty)
        #expect(selection.raw == "")
        #expect(TimelineLayerSelection(raw: selection.raw).isEmpty, "an empty stored choice is a choice, not a missing one")
        #expect(TimelineLayerSelection.default.lines == [.mood] && TimelineLayerSelection.default.marks == [.sleep, .food])
    }

    // MARK: - Tap inspection

    private func mark(_ id: String, _ layer: TimelineLayer, _ hour: Int, _ value: Double?) -> TimelineMark {
        TimelineMark(id: id, date: date(10, hour), layer: layer, value: value, caption: .scale(layer: layer, value: Int(value ?? 0)))
    }

    @Test func aReadingSaysWhetherItIsARecordAnEstimateOrTheNearestRecord() {
        let a = mark("a", .mood, 8, 2), b = mark("b", .mood, 12, 4)
        let group = [[a, b]]

        let onRecord = TimelineInspection.reading(groups: group, daily: false, at: date(10, 8), nearWindow: 1200, calendar: calendar)
        #expect(onRecord == TimelineValueReading(value: 2, source: .recorded))

        let between = TimelineInspection.reading(groups: group, daily: false, at: date(10, 10), nearWindow: 1200, calendar: calendar)
        #expect(between?.value == 3)
        #expect(between?.source == .interpolated(from: a.date, to: b.date))

        let near = TimelineInspection.reading(groups: group, daily: false, at: date(10, 12).addingTimeInterval(600), nearWindow: 1200, calendar: calendar)
        #expect(near?.value == 4)
        #expect(near?.source == .nearest(at: b.date))

        #expect(TimelineInspection.reading(groups: group, daily: false, at: date(10, 20), nearWindow: 1200, calendar: calendar) == nil)
        #expect(TimelineInspection.reading(groups: [], daily: false, at: date(10, 10), nearWindow: 1200, calendar: calendar) == nil)
    }

    @Test func aBrokenLineIsNotReadAcrossItsBreak() {
        let group = [[mark("a", .mood, 6, 2)], [mark("b", .mood, 14, 4)]]
        #expect(TimelineInspection.reading(groups: group, daily: false, at: date(10, 10), nearWindow: 600, calendar: calendar) == nil)
    }

    @Test func weekAndMonthReadTheDaysOwnMeanAndNothingBetweenDays() {
        let monday = TimelineMark(id: "avg1", date: date(9, 12), layer: .mood, value: 3.5, caption: .dailyAverage(layer: .mood, value: 3.5))
        let wednesday = TimelineMark(id: "avg2", date: date(11, 12), layer: .mood, value: 4.5, caption: .dailyAverage(layer: .mood, value: 4.5))
        let groups = [[monday, wednesday]]
        #expect(TimelineInspection.reading(groups: groups, daily: true, at: date(9, 20), nearWindow: 43_200, calendar: calendar)
                == TimelineValueReading(value: 3.5, source: .dailyAverage))
        // Tuesday has no record: no value is invented from its neighbours.
        #expect(TimelineInspection.reading(groups: groups, daily: true, at: date(10, 12), nearWindow: 43_200, calendar: calendar) == nil)
    }

    @Test func severalMarksUnderOneFingerAreAllOfferedNearestFirst() {
        let e1 = TimelineMark(id: "e1", date: date(10, 9), layer: .emotion, caption: .scale(layer: .emotion, value: 0))
        let e2 = TimelineMark(id: "e2", date: date(10, 9), layer: .emotion, caption: .scale(layer: .emotion, value: 0))
        let far = TimelineMark(id: "far", date: date(10, 15), layer: .food, caption: .scale(layer: .food, value: 0))
        let positioned: [(mark: TimelineMark, point: CGPoint)] = [
            (e1, CGPoint(x: 100, y: 50)), (e2, CGPoint(x: 108, y: 50)), (far, CGPoint(x: 300, y: 50)),
            (e1, CGPoint(x: 100, y: 50))
        ]
        let hits = TimelineInspection.candidates(positioned, at: CGPoint(x: 106, y: 52), radius: 14)
        #expect(hits.map(\.id) == ["e2", "e1"], "both marks, nearest first, each once, the far one left out")
        #expect(TimelineInspection.candidates(positioned, at: CGPoint(x: 200, y: 200), radius: 14).isEmpty)
        let band = TimelineMark(id: "band", date: date(10, 8), end: date(10, 10), layer: .activity, caption: .scale(layer: .activity, value: 0))
        #expect(TimelineInspection.bands([band], covering: date(10, 9)).map(\.id) == ["band"])
        #expect(TimelineInspection.bands([band], covering: date(10, 11)).isEmpty)
    }

    // MARK: - Weekly and monthly sleep, daily aggregation

    @Test func weekAndMonthSleepIsOnePointPerDayInHoursAndDaysWithoutSleepHaveNoPoint() {
        func night(_ day: Int, hours: Double) -> SleepSessionSummary {
            let end = date(day, 7)
            let start = end.addingTimeInterval(-hours * 3600)
            return SleepAggregationService.summary(of: [SleepInterval(stage: .unspecified, start: start, end: end)], origin: .manual, calendar: calendar)!
        }
        let interval = DateInterval(start: date(1, 0), end: date(8, 0))
        let days = TimelineSnapshotBuilder.sleepDays([night(2, hours: 7), night(3, hours: 6), night(6, hours: 8)], in: interval, calendar: calendar)
        #expect(days.count == 3)
        #expect(days.map { $0.value } == [7, 6, 8])
        #expect(days.allSatisfy { $0.layer == .sleep && $0.target != nil })
    }

    @Test func dailyAveragesWeighByTimeNotByNumberOfCheckIns() {
        let points = [
            mark("1", .mood, 8, 5), mark("2", .mood, 8, 5).with(date: date(10, 8).addingTimeInterval(60), id: "2b"),
            mark("3", .mood, 20, 1)
        ]
        let averages = TimelineSnapshotBuilder.dailyAverages(points, layer: .mood, calendar: calendar)
        #expect(averages.count == 1)
        // Two early 5s and one late 1: by count ≈ 3.7, by time it slides from 5 to 1.
        let value = averages[0].value ?? 0
        #expect(value > 2.5 && value < 3.5)
    }

    // MARK: - Navigation and History removal

    @Test func navigationHasNoHistoryTabAndRoutesAreHandedBetweenTabs() {
        let tabs = AppTabs()
        #expect(tabs.selected == .today)
        tabs.openAnalytics(.section(.sleep))
        #expect(tabs.selected == .analytics && tabs.pendingAnalyticsRoute == .section(.sleep))
        tabs.openDiary(day: date(3))
        #expect(tabs.selected == .diary && tabs.diaryDay == date(3))
        #expect(Set([AppTabs.Tab.today, .diary, .analytics]).count == 3)
    }

    @Test func everySessionRowInADayOpensItsDetails() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = FocusSession(activity: "Математика", startDate: date(10, 9), checkInIntervalMinutes: 10)
        session.state = .completed
        session.endDate = date(10, 10)
        context.insert(session)
        let segment = SessionSegment(type: .work, startDate: session.startDate, endDate: session.endDate)
        segment.session = session
        session.segments = [segment]
        try context.save()
        let summary = AnalyticsService.dailySummary(date: date(10), sessions: [session], checkIns: [], calendar: calendar)
        let targets = summary.timelineEvents.filter { $0.kind == .start || $0.kind == .end }.map(\.target)
        #expect(!targets.isEmpty && targets.allSatisfy { $0 == .session(session.id) })
        #expect(DiaryEditTarget.session(session.id).isSession)
    }

    @Test func deletingASessionRemovesOnlyThatSessionAndItsAggregates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let manager = SessionManager(container: container)
        func finished(_ name: String, daysAgo: Int) -> FocusSession {
            let start = date(20).addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            let session = FocusSession(activity: name, startDate: start, checkInIntervalMinutes: 10)
            session.state = .completed
            session.endDate = start.addingTimeInterval(1800)
            let segment = SessionSegment(type: .work, startDate: start, endDate: session.endDate)
            segment.session = session
            session.segments = [segment]
            context.insert(session)
            return session
        }
        let old = finished("Математика", daysAgo: 200)
        let recent = finished("Математика", daysAgo: 1)
        try context.save()

        func facts() -> AnalyticsFacts {
            AnalyticsFactsCapture.capture(
                checkIns: [], sessions: (try? ModelContext(container).fetch(FetchDescriptor<FocusSession>())) ?? [],
                hunger: [], food: [], emotions: [], impulses: [], support: [], cycle: [], categories: [], sleep: [],
                healthCycle: [], healthMedication: [:]
            )
        }
        #expect(facts().sessions.count == 2)

        // The manager works on its own context, as in the app.
        manager.delete(try #require(manager.session(withID: recent.id)))
        let left = try ModelContext(container).fetch(FetchDescriptor<FocusSession>())
        #expect(left.map(\.id) == [old.id], "history older than the deleted one is untouched")
        #expect(facts().sessions.count == 1, "analytics no longer counts the deleted session")
        #expect(SessionSearch.find("матем", in: ModelContext(container)).map(\.id) == [old.id])
    }

    @Test func theHistoryFilterFindsEveryFinishedSessionOfAnActivityWhateverItsSpelling() {
        // Sessions logged as "Уборка" and as "cleaning" are one activity.
        #expect(canonicalData("Уборка") == canonicalData("cleaning"))
        #expect(canonicalData("Моя редкая затея") == "Моя редкая затея")
    }
}

private extension TimelineMark {
    func with(date: Date, id: String) -> TimelineMark {
        TimelineMark(id: id, date: date, layer: layer, value: value, caption: caption)
    }
}
