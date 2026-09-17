import Foundation
import Testing
@testable import Mood_Pomodoro

@Suite
struct AnalyticsEngineTests {
    init() {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguage.storageKey)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 9, year: Int = 2024) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func interval(from start: Date, days: Int) -> DateInterval {
        let end = utc.date(byAdding: .day, value: days, to: utc.startOfDay(for: start))!
        return DateInterval(start: utc.startOfDay(for: start), end: end)
    }

    private func checkIn(
        id: UUID = UUID(),
        at timestamp: Date,
        mood: Double,
        moodRaw: String = Mood.neutral.rawValue,
        energy: Double? = nil,
        sessionID: UUID? = nil,
        reason: String? = nil,
        conditions: [AnalyticsConditionFact] = []
    ) -> AnalyticsCheckInFact {
        AnalyticsCheckInFact(
            id: id,
            timestamp: timestamp,
            mood: mood,
            moodRaw: moodRaw,
            energy: energy,
            motivation: nil,
            reason: reason,
            sessionID: sessionID,
            conditions: conditions
        )
    }

    private func session(
        id: UUID = UUID(),
        activity: String,
        type: String? = SessionType.study.rawValue,
        start: Date,
        minutes: Int
    ) -> AnalyticsSessionFact {
        AnalyticsSessionFact(
            id: id,
            activity: activity,
            typeRaw: type,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            stateRaw: SessionState.completed.rawValue,
            activeDuration: TimeInterval(minutes * 60),
            breakDuration: 0,
            checkInIDs: []
        )
    }

    private func facts(
        checkIns: [AnalyticsCheckInFact] = [],
        sessions: [AnalyticsSessionFact] = [],
        conditionEvents: [AnalyticsConditionEventFact] = [],
        hunger: [AnalyticsHungerFact] = [],
        food: [AnalyticsFoodFact] = [],
        emotions: [AnalyticsEmotionFact] = [],
        impulses: [AnalyticsImpulseFact] = [],
        support: [AnalyticsSupportFact] = [],
        cycle: [AnalyticsCycleFact] = [],
        sleep: [SleepSessionSummary] = [],
        healthMedication: [Date: String] = [:]
    ) -> AnalyticsFacts {
        AnalyticsFacts(
            checkIns: checkIns,
            sessions: sessions,
            conditionEvents: conditionEvents,
            hunger: hunger,
            food: food,
            emotions: emotions,
            impulses: impulses,
            support: support,
            cycle: cycle,
            sleep: sleep,
            categories: [],
            healthMedication: healthMedication
        )
    }

    private func night(
        day: Date,
        start: Date,
        end: Date,
        sleep: TimeInterval,
        deep: TimeInterval = 0,
        rem: TimeInterval = 0,
        core: TimeInterval = 0,
        id: String = "night"
    ) -> SleepSessionSummary {
        var stages: [SleepStage: TimeInterval] = [:]
        if deep > 0 { stages[.deep] = deep }
        if rem > 0 { stages[.rem] = rem }
        if core > 0 { stages[.core] = core }
        return SleepSessionSummary(
            id: id,
            day: utc.startOfDay(for: day),
            kind: .night,
            source: .manual,
            start: start,
            end: end,
            totalSleep: sleep,
            timeInBed: sleep,
            awake: 0,
            stageDurations: stages,
            awakeningCount: nil,
            intervals: [],
            sourceName: nil,
            sourceBundleIdentifier: nil,
            productType: nil
        )
    }

    private func snapshot(_ facts: AnalyticsFacts, from start: Date, days: Int, now: Date? = nil) -> AnalyticsSnapshot {
        let window = interval(from: start, days: days)
        return AnalyticsEngine.build(
            facts: facts,
            interval: window,
            previous: AnalyticsPeriod(kind: .days7).previousInterval(of: window, calendar: utc),
            calendar: utc,
            now: now ?? window.end.addingTimeInterval(-3600)
        )
    }

    // MARK: - Day-equal weighting

    @Test func daysWithDifferentCheckInCountsWeighTheSame() {
        let busy = (0..<10).map { checkIn(at: date(1, 8 + $0), mood: 5, moodRaw: Mood.veryGood.rawValue) }
        let quiet = [checkIn(at: date(2, 12), mood: 1, moodRaw: Mood.veryBad.rawValue)]
        let result = snapshot(facts(checkIns: busy + quiet), from: date(1), days: 2)
        #expect(result.overview.mood.dayCount == 2)
        #expect(result.overview.mood.observationCount == 11)
        #expect(abs((result.overview.mood.average ?? 0) - 3.0) < 0.01)
    }

    @Test func timeWeightedMoodDoesNotCrossADayBoundary() {
        let late = checkIn(at: date(1, 23), mood: 5, moodRaw: Mood.veryGood.rawValue)
        let early = checkIn(at: date(2, 1), mood: 1, moodRaw: Mood.veryBad.rawValue)
        let days = AnalyticsEngine.buildDays(
            facts: facts(checkIns: [late, early]),
            interval: interval(from: date(1), days: 2),
            calendar: utc,
            now: date(3)
        )
        #expect(days.count == 2)
        #expect(days[0].mood == 5)
        #expect(days[1].mood == 1)
        let crossed = AnalyticsEngine.timeWeightedAverage(
            points: [(late.timestamp, 5), (early.timestamp, 1)],
            start: utc.startOfDay(for: date(1)),
            end: utc.startOfDay(for: date(2)),
            maxGap: AnalyticsService.maximumMoodGap
        )
        #expect(crossed == 5)
    }

    @Test func sessionsWeighEquallyRegardlessOfCheckInCount() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let sessionA = session(id: a, activity: "Математика", start: date(1, 10), minutes: 60)
        let sessionB = session(id: b, activity: "Математика", start: date(2, 10), minutes: 60)
        var checkIns: [AnalyticsCheckInFact] = []
        for hour in 10..<20 {
            checkIns.append(checkIn(at: date(1, hour), mood: 5, moodRaw: Mood.veryGood.rawValue, sessionID: a))
        }
        checkIns.append(checkIn(at: date(2, 10), mood: 1, moodRaw: Mood.veryBad.rawValue, sessionID: b))
        checkIns.append(checkIn(at: date(2, 11), mood: 1, moodRaw: Mood.veryBad.rawValue, sessionID: b))
        let result = snapshot(facts(checkIns: checkIns, sessions: [sessionA, sessionB]), from: date(1), days: 2)
        let row = try! #require(result.activities.first)
        #expect(row.sessionCount == 2)
        #expect(abs((row.mood.average ?? 0) - 3.0) < 0.01)
    }

    @Test func oneMealIsCountedOnceEvenWithSeveralCheckIns() {
        let meal = AnalyticsFoodFact(id: UUID(), eventDate: date(1, 13), categoryRaw: FoodCategory.regular.rawValue, fullness: 4)
        let checkIns = [
            checkIn(at: date(1, 13, 10), mood: 5),
            checkIn(at: date(1, 13, 20), mood: 5),
            checkIn(at: date(1, 13, 40), mood: 1)
        ]
        let result = snapshot(facts(checkIns: checkIns, food: [meal]), from: date(1), days: 1)
        #expect(result.food.mealCount == 1)
        #expect(result.food.moodAfter.observationCount == 1)
        #expect(result.food.moodAfter.average == 5)
    }

    @Test func positiveFactorsRequireAPositiveMoodDelta() {
        let coffee = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
        let tea = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let cat = UUID(uuidString: "00000000-0000-0000-0000-0000000000CA")!
        func condition(_ option: UUID, _ name: String) -> AnalyticsConditionFact {
            AnalyticsConditionFact(categoryID: cat, optionID: option, categoryName: "Напиток", optionName: name, icon: "☕️", iconImageName: nil, categoryEnabled: true)
        }
        var checkIns: [AnalyticsCheckInFact] = []
        for day in 1...6 {
            checkIns.append(checkIn(at: date(day, 10), mood: 5, conditions: [condition(coffee, "Кофе")]))
        }
        for day in 7...12 {
            checkIns.append(checkIn(at: date(day, 10), mood: 1, conditions: [condition(tea, "Чай")]))
        }
        let result = snapshot(facts(checkIns: checkIns), from: date(1), days: 12)
        let positive = result.factors.filter { ($0.moodDelta ?? 0) > 0 }
        let negative = result.factors.filter { ($0.moodDelta ?? 0) < 0 }
        #expect(positive.contains { $0.optionName == "Кофе" })
        #expect(!positive.contains { $0.optionName == "Чай" })
        #expect(negative.contains { $0.optionName == "Чай" })
    }

    @Test func moodReasonDenominatorUsesAnsweredCheckInsOnly() {
        let answered = checkIn(at: date(1, 10), mood: 2, moodRaw: Mood.tired.rawValue, reason: "устала")
        let also = checkIn(at: date(1, 12), mood: 2, moodRaw: Mood.tired.rawValue, reason: "устала")
        let silent = checkIn(at: date(1, 14), mood: 2, moodRaw: Mood.tired.rawValue, reason: nil)
        let other = checkIn(at: date(1, 16), mood: 2, moodRaw: Mood.tired.rawValue, reason: "шум")
        let result = snapshot(facts(checkIns: [answered, also, silent, other]), from: date(1), days: 1)
        let tired = result.reasons.filter { $0.moodRaw == Mood.tired.rawValue }
        let row = try! #require(tired.first { $0.reason == "устала" })
        #expect(row.moodTotal == 4)
        #expect(row.answeredTotal == 3)
        #expect(row.count == 2)
        #expect(abs(row.percentageOfAnswered - (2.0 / 3.0)) < 0.001)
    }

    // MARK: - Period bounds

    @Test func periodStartIsInclusiveAndEndIsExclusive() {
        let period = AnalyticsPeriod(kind: .days7)
        let now = date(10, 15)
        let window = period.interval(now: now, calendar: utc)
        #expect(window.start == utc.startOfDay(for: date(4)))
        #expect(window.end == utc.startOfDay(for: date(11)))
        #expect(date(4, 0) >= window.start && date(4, 0) < window.end)
        #expect(!(date(11, 0) >= window.start && date(11, 0) < window.end))
    }

    @Test func periodUsesCalendarDaysNotFixedTwentyFourHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2024, month: 3, day: 12, hour: 15))!
        let window = AnalyticsPeriod(kind: .days7).interval(now: now, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: window.start, to: window.end).day == 7)
        let previous = AnalyticsPeriod(kind: .days7).previousInterval(of: window, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: previous.start, to: previous.end).day == 7)
        #expect(previous.end == window.start)
    }

    @Test func customPeriodRespectsTimeZones() {
        var moscow = Calendar(identifier: .gregorian)
        moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = moscow.date(from: DateComponents(year: 2024, month: 9, day: 1))!
        let end = moscow.date(from: DateComponents(year: 2024, month: 9, day: 2))!
        let period = AnalyticsPeriod(kind: .custom, customStart: start, customEnd: end)
        let moscowWindow = period.interval(now: end, calendar: moscow)
        let laWindow = period.interval(now: end, calendar: la)
        #expect(moscowWindow.start != laWindow.start)
        #expect(moscow.dateComponents([.day], from: moscowWindow.start, to: moscowWindow.end).day == 2)
    }

    // MARK: - Sleep

    @Test func overlappingSleepKeepsOneNight() {
        let day = date(16)
        let manual = night(day: day, start: date(15, 23), end: date(16, 8), sleep: 8 * 3600, id: "manual")
        var health = night(day: day, start: date(15, 23, 10), end: date(16, 7, 50), sleep: 7 * 3600, deep: 3600, id: "health")
        health = SleepSessionSummary(
            id: "health",
            day: health.day,
            kind: .night,
            source: .healthKit,
            start: health.start,
            end: health.end,
            totalSleep: health.totalSleep,
            timeInBed: health.timeInBed,
            awake: 0,
            stageDurations: [.deep: 3600],
            awakeningCount: nil,
            intervals: [],
            sourceName: nil,
            sourceBundleIdentifier: nil,
            productType: nil
        )
        let resolved = SleepAggregationService.resolveOverlaps(sessions: [manual, health])
        #expect(resolved.filter { !$0.isSuperseded }.count == 1)
        #expect(resolved.first { $0.id == "health" }?.isSuperseded == true)
    }

    @Test func deepSleepReportsMinutesAndShareSeparately() {
        let sleep = night(
            day: date(2),
            start: date(1, 23),
            end: date(2, 7),
            sleep: 8 * 3600,
            deep: 2 * 3600,
            rem: 2 * 3600,
            core: 4 * 3600,
            id: "staged"
        )
        #expect(sleep.hasStageDetail)
        #expect(sleep.duration(of: .deep) == 2 * 3600)
        let result = snapshot(facts(sleep: [sleep]), from: date(2), days: 1)
        #expect(result.sleep.nightCount == 1)
        #expect(abs((result.sleep.averageDeepSeconds ?? 0) - 2 * 3600) < 0.5)
        #expect(abs((result.sleep.averageDeepShare ?? 0) - 0.25) < 0.001)
        #expect(result.sleep.stagedNightCount == 1)
    }

    @Test func sleepBucketsRequireTheirOwnMinimumNights() {
        var checkIns: [AnalyticsCheckInFact] = []
        var nights: [SleepSessionSummary] = []
        for day in 1...14 {
            checkIns.append(checkIn(at: date(day, 12), mood: 4))
            nights.append(night(
                day: date(day),
                start: date(day, 0).addingTimeInterval(-8 * 3600),
                end: date(day, 7),
                sleep: 7.5 * 3600,
                id: "n\(day)"
            ))
        }
        nights.append(night(day: date(15), start: date(14, 23), end: date(15, 4), sleep: 4 * 3600, id: "short"))
        checkIns.append(checkIn(at: date(15, 12), mood: 2))
        let result = snapshot(facts(checkIns: checkIns, sleep: nights), from: date(1), days: 15)
        let short = try! #require(result.sleep.moodAfter.first { $0.id == "under6" })
        let mid = try! #require(result.sleep.moodAfter.first { $0.id == "6to8" })
        #expect(short.nightCount == 1)
        #expect(short.mood.confidence == .insufficient)
        #expect(mid.nightCount == 14)
        #expect(mid.mood.confidence == .descriptive)
    }

    @Test func untypedSessionsStayInTheirOwnGroup() {
        let typed = session(activity: "Учёба", type: SessionType.study.rawValue, start: date(1, 10), minutes: 40)
        let old = session(activity: "Что-то", type: nil, start: date(1, 16), minutes: 40)
        let result = snapshot(facts(sessions: [typed, old]), from: date(1), days: 1)
        #expect(result.activities.contains { $0.typeRaw == nil && $0.name == "Что-то" })
        #expect(result.activities.contains { $0.typeRaw == SessionType.study.rawValue })
        #expect(result.overview.untypedSeconds > 0)
    }

    @Test func missingMedicationIsNotTheSameAsNotTaken() {
        let taken = AnalyticsSupportFact(id: UUID(), day: utc.startOfDay(for: date(1)), statusRaw: SupportStatus.taken.rawValue)
        let skipped = AnalyticsSupportFact(id: UUID(), day: utc.startOfDay(for: date(2)), statusRaw: SupportStatus.notTaken.rawValue)
        let result = snapshot(
            facts(
                checkIns: [checkIn(at: date(1, 12), mood: 4), checkIn(at: date(2, 12), mood: 3), checkIn(at: date(3, 12), mood: 3)],
                support: [taken, skipped]
            ),
            from: date(1),
            days: 3
        )
        #expect(result.overview.supportTakenDays == 1)
        #expect(result.overview.supportSkippedDays == 1)
        let groups = AnalyticsEngine.compare(
            days: result.days,
            outcome: "mood",
            groups: [
                ("taken", "taken", { $0.supportRaw == SupportStatus.taken.rawValue }),
                ("skipped", "skipped", { $0.supportRaw == SupportStatus.notTaken.rawValue }),
                ("none", "none", { $0.supportRaw == nil })
            ]
        )
        #expect(groups.first { $0.id == "none" }?.dayCount == 1)
        #expect(groups.first { $0.id == "skipped" }?.dayCount == 1)
    }

    @Test func missingImpulseIsUnmarkedNotAbsent() {
        let impulse = AnalyticsImpulseFact(id: UUID(), eventDate: date(1, 15), categoryRaw: ImpulseCategory.food.rawValue, outcomeRaw: nil)
        let result = snapshot(
            facts(
                checkIns: [checkIn(at: date(1, 12), mood: 3), checkIn(at: date(2, 12), mood: 3)],
                impulses: [impulse]
            ),
            from: date(1),
            days: 2
        )
        #expect(result.overview.impulseDayCount == 1)
        let groups = AnalyticsEngine.compare(
            days: result.days,
            outcome: "mood",
            groups: [
                ("marked", "marked", { $0.impulseCount > 0 }),
                ("unmarked", "unmarked", { $0.impulseCount == 0 })
            ]
        )
        #expect(groups.first { $0.id == "unmarked" }?.dayCount == 1)
        #expect(groups.first { $0.id == "marked" }?.dayCount == 1)
    }

    @Test func computedRowIdsAreStable() {
        let cat = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let option = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
        let condition = AnalyticsConditionFact(categoryID: cat, optionID: option, categoryName: "Музыка", optionName: "Lo-fi", icon: "🎧", iconImageName: nil, categoryEnabled: true)
        let checkIns = (1...5).map { checkIn(at: date($0, 10), mood: 4, conditions: [condition]) }
        let first = snapshot(facts(checkIns: checkIns), from: date(1), days: 5)
        let second = snapshot(facts(checkIns: checkIns), from: date(1), days: 5)
        #expect(first.factors.map(\.id) == second.factors.map(\.id))
        #expect(first.factors.first?.id == AnalyticsEngine.factorID(category: cat, option: option))
        #expect(first.reasons.map(\.id) == second.reasons.map(\.id))
    }

    @Test func staleRebuildTokenIsDropped() {
        #expect(AnalyticsEngine.shouldPublish(token: 1, generation: 2) == false)
        #expect(AnalyticsEngine.shouldPublish(token: 4, generation: 4) == true)
    }

    @MainActor
    @Test func storeKeepsTheLatestPeriodAfterRapidChanges() async {
        let store = AnalyticsStore()
        let checkIns = (1...10).map { checkIn(at: date($0, 12), mood: 4) }
        store.ingest(facts(checkIns: checkIns), calendar: utc)
        store.period.kind = .days7
        store.period.kind = .days30
        try? await Task.sleep(nanoseconds: 250_000_000)
        let days = utc.dateComponents([.day], from: store.snapshot.interval.start, to: store.snapshot.interval.end).day
        #expect(days == 30)
    }

    @Test func midnightCrossingSessionSplitsAcrossDays() {
        let overnight = session(activity: "Работа", type: SessionType.obligatoryWork.rawValue, start: date(1, 22), minutes: 180)
        let split = AnalyticsEngine.splitSessionDurations(
            [overnight],
            interval: interval(from: date(1), days: 2),
            calendar: utc,
            now: date(3)
        )
        let first = split[utc.startOfDay(for: date(1))]?[SessionType.obligatoryWork.rawValue] ?? 0
        let second = split[utc.startOfDay(for: date(2))]?[SessionType.obligatoryWork.rawValue] ?? 0
        #expect(first > 0)
        #expect(second > 0)
        #expect(abs(first + second - 180 * 60) < 1)
    }

    @Test func largeHistoryBuildsWithoutCrossingASecond() {
        var checkIns: [AnalyticsCheckInFact] = []
        var sessions: [AnalyticsSessionFact] = []
        var food: [AnalyticsFoodFact] = []
        var sleep: [SleepSessionSummary] = []
        var emotions: [AnalyticsEmotionFact] = []
        var impulses: [AnalyticsImpulseFact] = []
        let startDay = date(1, 0, month: 1)
        for dayIndex in 0..<365 {
            let day = utc.date(byAdding: .day, value: dayIndex, to: startDay)!
            for hour in [9, 14, 21] {
                checkIns.append(checkIn(at: utc.date(byAdding: .hour, value: hour, to: day)!, mood: Double((dayIndex % 5) + 1)))
            }
            let sessionStart = utc.date(byAdding: .hour, value: 10, to: day)!
            sessions.append(session(activity: dayIndex % 2 == 0 ? "Учёба" : "Отдых", type: dayIndex % 3 == 0 ? nil : SessionType.study.rawValue, start: sessionStart, minutes: 50))
            food.append(AnalyticsFoodFact(id: UUID(), eventDate: utc.date(byAdding: .hour, value: 13, to: day)!, categoryRaw: FoodCategory.regular.rawValue, fullness: 3))
            sleep.append(night(day: day, start: utc.date(byAdding: .hour, value: -8, to: day)!, end: utc.date(byAdding: .hour, value: 7, to: day)!, sleep: 7 * 3600, deep: 3600, id: "s\(dayIndex)"))
            if dayIndex % 4 == 0 {
                emotions.append(AnalyticsEmotionFact(id: UUID(), eventDate: utc.date(byAdding: .hour, value: 16, to: day)!, emotions: [Emotion.anxious.rawValue]))
            }
            if dayIndex % 5 == 0 {
                impulses.append(AnalyticsImpulseFact(id: UUID(), eventDate: utc.date(byAdding: .hour, value: 19, to: day)!, categoryRaw: ImpulseCategory.food.rawValue, outcomeRaw: nil))
            }
        }
        while sessions.count < 1000 {
            let extra = sessions.count
            sessions.append(session(activity: "Доп", start: utc.date(byAdding: .hour, value: extra % 20, to: startDay)!, minutes: 25))
        }
        let window = DateInterval(start: startDay, end: utc.date(byAdding: .day, value: 365, to: startDay)!)
        let started = CFAbsoluteTimeGetCurrent()
        let result = AnalyticsEngine.build(
            facts: facts(checkIns: checkIns, sessions: sessions, food: food, emotions: emotions, impulses: impulses, sleep: sleep),
            interval: window,
            previous: nil,
            calendar: utc,
            now: window.end
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        #expect(result.days.count > 300)
        #expect(result.overview.checkInCount == checkIns.count)
        #expect(elapsed < 2.0)
    }
}
