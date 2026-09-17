import Foundation
import Testing
@testable import Mood_Pomodoro

@MainActor
struct ExportCompletenessTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func options(
        start: Date,
        end: Date,
        format: ExportFormat = .json,
        includeHealth: Bool = false,
        includeNotes: Bool = true
    ) -> ExportOptions {
        ExportOptions(
            start: start,
            end: end,
            language: .en,
            format: format,
            includeNotes: includeNotes,
            includeHealth: includeHealth
        )
    }

    private func sleepSummary(
        start: Date,
        end: Date,
        source: SleepSource,
        stages: [SleepInterval]? = nil,
        superseded: Bool = false
    ) -> SleepSessionSummary {
        var summary = SleepAggregationService.summary(
            of: stages ?? [SleepInterval(stage: .unspecified, start: start, end: end)],
            origin: source,
            calendar: calendar
        )!
        summary.isSuperseded = superseded
        if superseded { summary.supersededBy = .manual }
        return summary
    }

    private func completedSession(start: Date, end: Date, activity: String = "Code") -> FocusSession {
        let session = FocusSession(activity: activity, startDate: start, checkInIntervalMinutes: 10)
        session.endDate = end
        session.state = .completed
        session.sessionType = .study
        let work = SessionSegment(type: .work, startDate: start, endDate: end)
        work.session = session
        session.segments = [work]
        return session
    }

    private func fixtureInput() -> ExportInput {
        let session = completedSession(start: date(2, 9), end: date(2, 11))
        let crossing = completedSession(start: date(1, 22), end: date(2, 6), activity: "Night work")
        let active = FocusSession(activity: "Now", startDate: date(8, 8), checkInIntervalMinutes: 10)
        active.state = .active
        let open = SessionSegment(type: .work, startDate: date(8, 8))
        open.session = active
        active.segments = [open]

        let checkIn = CheckIn(timestamp: date(2, 10), mood: .good, energy: .high, motivation: .medium, origin: .scheduled)
        checkIn.session = session
        session.checkIns = [checkIn]
        checkIn.conditionSnapshot = [
            ConditionSnapshotEntry(
                categoryID: UUID(),
                categoryName: "Чай",
                categoryIcon: "🍵",
                categoryIconImageName: nil,
                optionID: UUID(),
                optionName: "Пуэр",
                optionIconImageName: nil
            )
        ]

        let standaloneCheckIn = CheckIn(timestamp: date(3, 15), mood: .tired, note: "late")
        let emotion = EmotionEntry(eventDate: date(3, 16), emotions: [.anxious, .interested], note: "both")
        let hunger = HungerEntry(eventDate: date(3, 12), hunger: .hungry, appetite: nil)
        let food = FoodEntry(eventDate: date(3, 13), category: .regular, mealDensity: .filling, taste: .tasty, desc: "pasta")
        let impulse = ImpulseEntry(eventDate: date(3, 18), category: .purchase, strength: .strong, outcome: .wanted)
        let note = JournalNote(timestamp: date(3, 20), text: "line1\nline2 ✨")
        let cycle = CycleEntry(date: date(2), kind: .periodStart, note: "started", calendar: calendar)
        let support = SupportEntry(day: date(3), status: .taken, time: date(3, 9), note: "ok", calendar: calendar)
        let factor = ConditionEvent(timestamp: date(3, 14), category: FactorCategory(name: "Музыка", icon: "🎵"), option: FactorOption(name: "Lo-fi", icon: "🎶"))
        let manualNight = sleepSummary(start: date(2, 23), end: date(3, 7), source: .manual)
        var healthNight = sleepSummary(
            start: date(2, 23, 10),
            end: date(3, 7, 10),
            source: .healthKit,
            stages: [
                SleepInterval(stage: .core, start: date(2, 23, 10), end: date(3, 2)),
                SleepInterval(stage: .deep, start: date(3, 2), end: date(3, 4)),
                SleepInterval(stage: .rem, start: date(3, 4), end: date(3, 7, 10))
            ],
            superseded: true
        )
        healthNight.quality = .good

        return ExportInput(
            sessions: [session, crossing, active],
            checkIns: [checkIn, standaloneCheckIn],
            cycleEntries: [cycle],
            supportEntries: [support],
            notes: [note],
            conditionEvents: [factor],
            foodEntries: [food],
            hungerEntries: [hunger],
            emotionEntries: [emotion],
            impulseEntries: [impulse],
            sleep: [manualNight, healthNight],
            healthCycleDays: [
                ExportHealthCycleCapture(day: date(2), kind: .periodStart, flow: .medium, isCycleStart: true, sourceName: "Health")
            ],
            healthMedication: [
                ExportHealthMedCapture(day: date(4), takenCount: 1, skippedCount: 1, status: .partial, detail: "1+1", sourceName: "Health")
            ]
        )
    }

    @Test func jsonRoundTripsThroughCodable() throws {
        let text = DiaryExporter.export(fixtureInput(), options: options(start: date(2), end: date(8), includeHealth: true), calendar: calendar, now: date(8, 12))
        let decoded = try DiaryExporter.decode(text)
        #expect(decoded.schemaVersion == 2)
        let again = DiaryExporter.encode(decoded)
        let decodedAgain = try DiaryExporter.decode(again)
        #expect(decodedAgain.checkIns.count == decoded.checkIns.count)
        #expect(decodedAgain.sessions.count == decoded.sessions.count)
    }

    @Test func jsonContainsEveryModelKind() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8), includeHealth: true), calendar: calendar, now: date(8, 12))
        #expect(!document.checkIns.isEmpty)
        #expect(!document.emotions.isEmpty)
        #expect(!document.hungerAppetite.isEmpty)
        #expect(!document.food.isEmpty)
        #expect(!document.impulses.isEmpty)
        #expect(!document.sessions.isEmpty)
        #expect(!document.standaloneConditions.isEmpty)
        #expect(!document.supportEntries.isEmpty)
        #expect(!document.cycleEntries.isEmpty)
        #expect(!document.healthCycleMarks.isEmpty)
        #expect(!document.healthMedicationDays.isEmpty)
        #expect(!document.notes.isEmpty)
        #expect(!document.sleep.isEmpty)
        #expect(document.days.contains { $0.hasData })
    }

    @Test func markdownContainsEveryDataKind() {
        let text = DiaryExporter.export(fixtureInput(), options: options(start: date(2), end: date(8), format: .markdown, includeHealth: true), calendar: calendar, now: date(8, 12))
        #expect(text.contains("Good (4/5)"))
        #expect(text.contains("Anxious"))
        #expect(text.contains("Hunger: 4/5"))
        #expect(text.contains("pasta"))
        #expect(text.contains("Shopping"))
        #expect(text.contains("Night work"))
        #expect(text.contains("Daily support: Taken"))
        #expect(text.contains("Period — day 1") || text.contains("Cycle day"))
        #expect(text.contains("line1"))
        #expect(text.contains("Night sleep"))
        #expect(text.contains("Now"))
    }

    @Test func unansweredScaleStaysNullNotMidpoint() throws {
        let hunger = HungerEntry(eventDate: date(3, 12), hunger: .hungry, appetite: nil)
        let document = DiaryExporter.assemble(
            ExportInput(hungerEntries: [hunger]),
            options: options(start: date(3), end: date(3)),
            calendar: calendar,
            now: date(8, 12)
        )
        #expect(document.hungerAppetite.first?.hunger?.value == 4)
        #expect(document.hungerAppetite.first?.appetite == nil)
    }

    @Test func unrecordedSupportIsNotNotTaken() throws {
        let taken = SupportEntry(day: date(3), status: .taken, calendar: calendar)
        let document = DiaryExporter.assemble(
            ExportInput(supportEntries: [taken]),
            options: options(start: date(3), end: date(4)),
            calendar: calendar,
            now: date(8, 12)
        )
        let day3 = try #require(document.days.first { $0.date == "2024-09-03" })
        let day4 = try #require(document.days.first { $0.date == "2024-09-04" })
        #expect(day3.support.status == SupportStatus.taken.rawValue)
        #expect(day4.support.status == "unrecorded")
        #expect(day4.support.status != SupportStatus.notTaken.rawValue)
    }

    @Test func healthSleepExportsWhenEnabledAndDropsWhenDisabled() throws {
        let input = fixtureInput()
        let withHealth = DiaryExporter.assemble(input, options: options(start: date(2), end: date(8), includeHealth: true), calendar: calendar, now: date(8, 12))
        let without = DiaryExporter.assemble(input, options: options(start: date(2), end: date(8), includeHealth: false), calendar: calendar, now: date(8, 12))
        #expect(withHealth.sleep.contains { $0.source == SleepSource.healthKit.rawValue })
        #expect(withHealth.sleep.contains { $0.source == SleepSource.manual.rawValue })
        #expect(!without.sleep.contains { $0.source == SleepSource.healthKit.rawValue })
        #expect(without.sleep.contains { $0.source == SleepSource.manual.rawValue })
        #expect(without.healthCycleMarks.isEmpty)
        #expect(!withHealth.healthCycleMarks.isEmpty)
    }

    @Test func supersededSleepIsListedButExcludedFromTotals() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8), includeHealth: true), calendar: calendar, now: date(8, 12))
        let superseded = try #require(document.sleep.first { $0.isSuperseded })
        #expect(superseded.countedInTotals == false)
        #expect(document.summary.nightSleepSeconds == document.sleep.filter { $0.countedInTotals && $0.kind.raw == "night" }.reduce(0) { $0 + $1.totalSleepSeconds })
    }

    @Test func sleepStagesAreNotDoubleCountedInSummary() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8), includeHealth: true), calendar: calendar, now: date(8, 12))
        let counted = document.sleep.filter { $0.countedInTotals && $0.kind.raw == "night" }
        let core = counted.reduce(0.0) { $0 + $1.coreDurationSeconds }
        #expect(document.summary.sleepStagesSeconds["core"] == core)
    }

    @Test func sessionCrossingPeriodStartIsExported() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        #expect(document.sessions.contains { $0.activity == "Night work" })
        let crossing = try #require(document.sessions.first { $0.activity == "Night work" })
        #expect(crossing.overlapDurationSeconds > 0)
        #expect(crossing.overlapDurationSeconds < crossing.totalDurationSeconds)
    }

    @Test func overnightSleepUsesWakeDay() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        let night = try #require(document.sleep.first { $0.source == SleepSource.manual.rawValue })
        #expect(night.day == "2024-09-03")
        #expect(night.start.contains("2024-09-02"))
    }

    @Test func activeSessionHasNullEndAndCalculatedThrough() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        let active = try #require(document.sessions.first { $0.activity == "Now" })
        #expect(active.end == nil)
        #expect(active.calculatedThrough == "2024-09-08T12:00:00Z")
        #expect(active.state == SessionState.active.rawValue)
        #expect(active.segments.contains { $0.end == nil })
    }

    @Test func notesKeepNewlinesAndUnicode() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        #expect(document.notes.first?.text == "line1\nline2 ✨")
        let markdown = DiaryExporter.export(fixtureInput(), options: options(start: date(2), end: date(8), format: .markdown), calendar: calendar, now: date(8, 12))
        #expect(markdown.contains("line1"))
        #expect(markdown.contains("✨"))
    }

    @Test func emotionsAndImpulsesCarryRawAndLabels() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        let emotion = try #require(document.emotions.first)
        #expect(emotion.emotions.contains { $0.raw == "anxious" && $0.label == "Anxious" && !$0.emoji.isEmpty })
        let impulse = try #require(document.impulses.first)
        #expect(impulse.category.raw == "purchase")
        #expect(impulse.category.label == "Shopping")
        #expect(impulse.strength?.raw == "strong")
        #expect(impulse.outcome?.raw == "wanted")
    }

    @Test func inputOrderDoesNotChangeCanonicalJSON() {
        let input = fixtureInput()
        var reversed = input
        reversed.checkIns = input.checkIns.reversed()
        reversed.sessions = input.sessions.reversed()
        reversed.sleep = input.sleep.reversed()
        let a = DiaryExporter.assemble(input, options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        let b = DiaryExporter.assemble(reversed, options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        #expect(a.checkIns.map(\.id) == b.checkIns.map(\.id))
        #expect(a.sessions.map(\.id) == b.sessions.map(\.id))
        #expect(a.sleep.map(\.id) == b.sleep.map(\.id))
        #expect(a.summary.checkInCount == b.summary.checkInCount)
    }

    @Test func dataOutsideThePeriodIsAbsent() throws {
        let outside = CheckIn(timestamp: date(1, 10), mood: .veryGood)
        var input = fixtureInput()
        input.checkIns.append(outside)
        let document = DiaryExporter.assemble(input, options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        #expect(!document.checkIns.contains { $0.mood.raw == Mood.veryGood.rawValue })
    }

    @Test func markdownDayEventsAreChronological() {
        let text = DiaryExporter.export(fixtureInput(), options: options(start: date(3), end: date(3), format: .markdown), calendar: calendar, now: date(8, 12))
        let stamps = text.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("- "), line.contains(" · ") else { return nil }
            let time = line.dropFirst(2).prefix(8)
            return time.contains(":") ? String(time) : nil
        }
        #expect(stamps == stamps.sorted())
    }

    @Test func largeExportDoesNotNeedMainActorForRendering() async {
        var checkIns: [CheckIn] = []
        for day in 1...28 {
            for hour in [9, 13, 18, 22] {
                checkIns.append(CheckIn(timestamp: date(min(day, 28), hour), mood: .good))
            }
        }
        let input = ExportInput(checkIns: checkIns)
        let options = options(start: date(1), end: date(28), format: .markdown)
        let document = DiaryExporter.assemble(input, options: options, calendar: calendar, now: date(28, 23))
        let started = Date()
        let text = await Task.detached {
            DiaryExporter.render(document, options: options, calendar: Calendar(identifier: .gregorian))
        }.value
        let ms = Date().timeIntervalSince(started) * 1000
        print("BENCH export_markdown_ms=\(ms) chars=\(text.count)")
        #expect(!text.isEmpty)
        #expect(ms < 2000)
    }

    @Test func cycleNoteSurvives() throws {
        let document = DiaryExporter.assemble(fixtureInput(), options: options(start: date(2), end: date(8)), calendar: calendar, now: date(8, 12))
        #expect(document.cycleEntries.first?.note == "started")
    }

    @Test func foodDoesNotInventHungerLinkOutsideWindow() throws {
        let hunger = HungerEntry(eventDate: date(3, 8), hunger: .hungry)
        let food = FoodEntry(eventDate: date(3, 13), category: .regular)
        let document = DiaryExporter.assemble(
            ExportInput(foodEntries: [food], hungerEntries: [hunger]),
            options: options(start: date(3), end: date(3)),
            calendar: calendar,
            now: date(8, 12)
        )
        #expect(document.food.first?.hungerBefore == nil)
    }
}
