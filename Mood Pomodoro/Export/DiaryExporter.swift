import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json

    var id: String { rawValue }
    var fileExtension: String { self == .markdown ? "md" : "json" }
}

struct ExportOptions: Equatable, Sendable {
    var start: Date
    var end: Date
    var language: AppLanguage
    var format: ExportFormat = .markdown
    var includeAIPrompt = true
    var includeNotes = true
    var includeCycle = true
    var includeSupport = true
    var includeFood = true
    var includeHealth = false
}

struct ExportHealthCycleCapture: Sendable {
    var day: Date
    var kind: CycleEventKind
    var flow: MenstrualFlow?
    var isCycleStart: Bool
    var sourceName: String?
}

struct ExportHealthMedCapture: Sendable {
    var day: Date
    var takenCount: Int
    var skippedCount: Int
    var status: SupportStatus?
    var detail: String?
    var sourceName: String?
}

/// SwiftData-backed bag used on the actor that owns the models. Copied into
/// a `MoodPomodoroExport` before any background formatting.
struct ExportInput {
    var sessions: [FocusSession] = []
    var checkIns: [CheckIn] = []
    var cycleEntries: [CycleEntry] = []
    var supportEntries: [SupportEntry] = []
    var notes: [JournalNote] = []
    var conditionEvents: [ConditionEvent] = []
    var foodEntries: [FoodEntry] = []
    var hungerEntries: [HungerEntry] = []
    var emotionEntries: [EmotionEntry] = []
    var impulseEntries: [ImpulseEntry] = []
    var sleep: [SleepSessionSummary] = []
    var healthCycleDays: [ExportHealthCycleCapture] = []
    var healthMedication: [ExportHealthMedCapture] = []

    /// Back-compat for tests that still pass `manualSleep`.
    var manualSleep: [SleepSessionSummary] {
        get { sleep }
        set { sleep = newValue }
    }

    var earliestDate: Date? {
        let dates = sessions.map(\.startDate) + checkIns.map(\.timestamp) + cycleEntries.map(\.date)
            + supportEntries.map(\.day) + notes.map(\.timestamp) + conditionEvents.map(\.timestamp)
            + foodEntries.map(\.eventDate) + hungerEntries.map(\.eventDate)
            + emotionEntries.map(\.eventDate) + impulseEntries.map(\.eventDate)
            + sleep.map(\.start)
        return dates.min()
    }
}

enum DiaryExporter {
    static let schemaVersion = 2

    static func export(
        _ input: ExportInput,
        options: ExportOptions,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        AppLanguage.$override.withValue(options.language) {
            let document = ExportAssembler(input: input, options: options, calendar: calendar, now: now).document()
            return render(document, options: options, calendar: calendar)
        }
    }

    static func assemble(
        _ input: ExportInput,
        options: ExportOptions,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> MoodPomodoroExport {
        AppLanguage.$override.withValue(options.language) {
            ExportAssembler(input: input, options: options, calendar: calendar, now: now).document()
        }
    }

    nonisolated static func render(_ document: MoodPomodoroExport, options: ExportOptions, calendar: Calendar = .current) -> String {
        AppLanguage.$override.withValue(options.language) {
            switch options.format {
            case .markdown: return ExportMarkdown.render(document, options: options, calendar: calendar)
            case .json: return encode(document)
            }
        }
    }

    nonisolated static func encode(_ document: MoodPomodoroExport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(document), let text = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return text.hasSuffix("\n") ? text : text + "\n"
    }

    nonisolated static func decode(_ text: String) throws -> MoodPomodoroExport {
        try JSONDecoder().decode(MoodPomodoroExport.self, from: Data(text.utf8))
    }

    static func fileName(for options: ExportOptions, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: min(options.start, options.end))
        let end = formatter.string(from: max(options.start, options.end))
        return "mood-diary_\(start)_\(end).\(options.format.fileExtension)"
    }
}

// MARK: - Dates

private struct ExportClock {
    let calendar: Calendar

    var iso: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    var day: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    func instant(_ date: Date) -> String { iso.string(from: date) }
    func dayString(_ date: Date) -> String { day.string(from: calendar.startOfDay(for: date)) }
}

// MARK: - Labels

private enum ExportMap {
    static func mood(_ value: Mood) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func energy(_ value: EnergyLevel) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func motivation(_ value: StudyMotivation) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func hunger(_ value: HungerLevel) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func appetite(_ value: AppetiteLevel) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func fullness(_ value: Fullness) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func quality(_ value: SleepQuality) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func strength(_ value: ImpulseStrength) -> ExportScaleValue {
        ExportScaleValue(raw: value.rawValue, value: Int(value.scale), label: value.label, emoji: value.emoji)
    }
    static func labeled(_ raw: String, _ label: String, emoji: String? = nil, glyph: String? = nil) -> ExportLabeled {
        ExportLabeled(raw: raw, label: label, emoji: emoji, glyph: glyph)
    }
    static func emotion(_ value: Emotion) -> ExportEmotionDef {
        ExportEmotionDef(raw: value.rawValue, label: value.label, emoji: value.emoji, colorHex: colorHex(value))
    }
    static func sessionType(_ type: SessionType?) -> ExportLabeled {
        labeled(type?.rawValue ?? "unassigned", SessionType.label(for: type), emoji: SessionType.emoji(for: type))
    }
    static func condition(_ entry: ConditionSnapshotEntry) -> ExportConditionRef {
        ExportConditionRef(
            categoryId: entry.categoryID.uuidString,
            categoryRaw: Ldata(entry.categoryName),
            optionId: entry.optionID.uuidString,
            optionRaw: Ldata(entry.optionName),
            icon: entry.categoryIcon,
            iconImageName: entry.resolvedIconImageName
        )
    }
    static func colorHex(_ emotion: Emotion) -> String {
        switch emotion {
        case .calm: return "#7C8B5A"
        case .angry: return "#B44232"
        case .sad: return "#5B769A"
        case .happy: return "#E1A938"
        case .anxious: return "#7E609A"
        case .bored: return "#8F8C73"
        case .interested: return "#3E8984"
        }
    }
}

// MARK: - Assemble

private struct ExportAssembler {
    let input: ExportInput
    let options: ExportOptions
    let calendar: Calendar
    let now: Date
    let clock: ExportClock

    init(input: ExportInput, options: ExportOptions, calendar: Calendar, now: Date) {
        self.input = input
        self.options = options
        self.calendar = calendar
        self.now = now
        self.clock = ExportClock(calendar: calendar)
    }

    var interval: DateInterval {
        let start = calendar.startOfDay(for: min(options.start, options.end))
        let lastDay = calendar.startOfDay(for: max(options.start, options.end))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return DateInterval(start: start, end: end)
    }

    var days: [Date] {
        var result: [Date] = []
        var day = interval.start
        while day < interval.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    func instant(_ date: Date) -> Bool { date >= interval.start && date < interval.end }
    func calendarDay(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= interval.start && day < interval.end
    }
    func overlaps(_ start: Date, _ end: Date) -> Bool { start < interval.end && end > interval.start }
    func clipped(_ start: Date, _ end: Date) -> TimeInterval {
        let lo = max(start, interval.start)
        let hi = min(end, interval.end)
        return max(0, hi.timeIntervalSince(lo))
    }

    func document() -> MoodPomodoroExport {
        let sleepSource = options.includeHealth ? input.sleep : input.sleep.filter { $0.source == .manual }
        let healthCycle = options.includeHealth && options.includeCycle ? input.healthCycleDays : []
        let healthMeds = options.includeHealth && options.includeSupport ? input.healthMedication : []
        let cycleEntries = options.includeCycle ? input.cycleEntries.filter { calendarDay($0.date) } : []
        let supportEntries = options.includeSupport ? input.supportEntries.filter { calendarDay($0.day) } : []
        let notes = options.includeNotes ? input.notes.filter { instant($0.timestamp) } : []
        let food = options.includeFood ? input.foodEntries.filter { instant($0.eventDate) } : []
        let hunger = options.includeFood ? input.hungerEntries.filter { !$0.isEmpty && instant($0.eventDate) } : []
        let emotions = input.emotionEntries.filter { !$0.isEmpty && instant($0.eventDate) }
        let impulses = input.impulseEntries.filter { instant($0.eventDate) }
        let checkIns = input.checkIns.filter { instant($0.timestamp) }
        let sessions = input.sessions.filter { session in
            overlaps(session.startDate, session.endDate ?? now)
        }
        let standalone = input.conditionEvents.filter { $0.session == nil && instant($0.timestamp) }
        let sleepRows = sleepSource.filter { overlaps($0.start, $0.end) }

        let exportCheckIns = checkIns.sorted { $0.timestamp < $1.timestamp }.map(mapCheckIn)
        let exportEmotions = emotions.sorted { $0.eventDate < $1.eventDate }.map(mapEmotion)
        let exportHunger = hunger.sorted { $0.eventDate < $1.eventDate }.map(mapHunger)
        let exportFood = food.sorted { $0.eventDate < $1.eventDate }.map { mapFood($0, hunger: hunger) }
        let exportImpulses = impulses.sorted { $0.eventDate < $1.eventDate }.map(mapImpulse)
        let exportSessions = sessions.sorted { $0.startDate < $1.startDate }.map { mapSession($0, checkIns: checkIns) }
        let exportStandalone = standalone.sorted { $0.timestamp < $1.timestamp }.map(mapConditionEvent)
        let exportSupport = supportEntries.sorted { $0.day < $1.day }.map(mapSupport)
        let exportHealthMeds = healthMeds.sorted { $0.day < $1.day }.map(mapHealthMed)
        let exportCycle = cycleEntries.sorted { $0.date < $1.date }.map(mapCycle)
        let exportHealthCycle = healthCycle.sorted { $0.day < $1.day }.map(mapHealthCycle)
        let exportNotes = notes.sorted { $0.timestamp < $1.timestamp }.map(mapNote)
        let exportSleep = sleepRows.sorted { $0.start < $1.start }.map(mapSleep)

        let healthMarks = healthCycle.map { CycleMark(day: $0.day, kind: $0.kind, source: .healthKit) }
        let healthMedByDay = Dictionary(uniqueKeysWithValues: healthMeds.map { (calendar.startOfDay(for: $0.day), $0) })

        let exportDays = days.map { day in
            mapDay(
                day,
                checkIns: checkIns,
                sessions: sessions,
                emotions: emotions,
                hunger: hunger,
                food: food,
                impulses: impulses,
                notes: notes,
                standalone: standalone,
                sleep: sleepRows,
                cycleEntries: cycleEntries,
                supportEntries: supportEntries,
                healthMarks: healthMarks,
                healthCycle: healthCycle,
                healthMedByDay: healthMedByDay
            )
        }

        let excluded = excludedToggles()
        return MoodPomodoroExport(
            schemaVersion: DiaryExporter.schemaVersion,
            app: "Mood Pomodoro",
            exportedAt: clock.instant(now),
            timezone: calendar.timeZone.identifier,
            locale: options.language.rawValue,
            requestedPeriod: ExportPeriod(
                start: clock.dayString(interval.start),
                end: clock.dayString(days.last ?? interval.start),
                startInstant: clock.instant(interval.start),
                endExclusive: clock.instant(interval.end),
                dayCount: days.count
            ),
            privacy: ExportPrivacy(
                includeNotes: options.includeNotes,
                includeCycle: options.includeCycle,
                includeSupport: options.includeSupport,
                includeFood: options.includeFood,
                includeHealth: options.includeHealth,
                excludedByToggles: excluded,
                notes: privacyNotes()
            ),
            definitions: definitions(),
            summary: summarize(days: exportDays, checkIns: exportCheckIns, sessions: exportSessions, sleep: exportSleep),
            days: exportDays,
            checkIns: exportCheckIns,
            emotions: exportEmotions,
            hungerAppetite: exportHunger,
            food: exportFood,
            impulses: exportImpulses,
            sessions: exportSessions,
            standaloneConditions: exportStandalone,
            supportEntries: exportSupport,
            healthMedicationDays: exportHealthMeds,
            cycleEntries: exportCycle,
            healthCycleMarks: exportHealthCycle,
            notes: exportNotes,
            sleep: exportSleep
        )
    }

    func excludedToggles() -> [String] {
        var items: [String] = []
        if !options.includeNotes { items.append("notes") }
        if !options.includeCycle { items.append("cycle") }
        if !options.includeSupport { items.append("support") }
        if !options.includeFood { items.append("foodHungerAppetite") }
        if !options.includeHealth { items.append("appleHealth") }
        return items
    }

    func privacyNotes() -> [String] {
        [
            L("Файл создаётся только по твоему действию и никуда сам не отправляется.", "The file is created only when you ask, and is never sent anywhere by itself."),
            L("Данные Apple Health не синхронизируются через iCloud этим приложением.", "Apple Health data is not synced through iCloud by this app."),
            L("Пропуск — это отсутствие ответа, а не среднее значение шкалы.", "A missing answer is an absence, not the middle of a scale.")
        ]
    }

    func definitions() -> ExportDefinitions {
        ExportDefinitions(
            mood: Mood.orderedCases.map(ExportMap.mood),
            energy: EnergyLevel.orderedCases.map(ExportMap.energy),
            motivation: StudyMotivation.orderedCases.map(ExportMap.motivation),
            hunger: HungerLevel.orderedCases.map(ExportMap.hunger),
            appetite: AppetiteLevel.orderedCases.map(ExportMap.appetite),
            fullness: Fullness.orderedCases.map(ExportMap.fullness),
            sleepQuality: SleepQuality.orderedCases.map(ExportMap.quality),
            impulseStrength: ImpulseStrength.orderedCases.map(ExportMap.strength),
            emotions: Emotion.allCases.map(ExportMap.emotion),
            foodCategories: FoodCategory.allCases.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            impulseCategories: ImpulseCategory.allCases.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            impulseOutcomes: ImpulseOutcome.allCases.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            supportStatuses: SupportStatus.allCases.map { ExportMap.labeled($0.rawValue, $0.label, glyph: $0.glyph) },
            cycleEventKinds: CycleEventKind.allCases.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.icon) },
            sessionTypes: SessionType.allCases.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) }
                + [ExportMap.sessionType(nil)],
            sessionStates: [SessionState.active, .paused, .completed, .cancelled].map { ExportMap.labeled($0.rawValue, $0.rawValue) },
            sleepKinds: [SleepKind.night, .nap].map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            sleepStages: SleepStage.allCases.map { ExportMap.labeled($0.rawValue, $0.label) },
            rules: [
                L("Ночь относится к дню пробуждения.", "A night belongs to the calendar day the person woke up."),
                L("totalSleep не включает awake и timeInBed.", "totalSleep does not include awake or timeInBed."),
                L("Ручная запись перекрывает Apple Health там, где они описывают одну ночь или один день.", "A manual record wins over Apple Health where they describe the same night or day."),
                L("Оценка качества сна субъективна и не вычисляется из часов или фаз.", "Sleep quality is subjective and is never computed from hours or stages."),
                L("Средние по дням: каждый день с данными имеет одинаковый вес.", "Day-level averages: each day with data has equal weight."),
                L("Среднее настроение периода по check-in взвешено по времени (промежуток не больше 6 часов).", "Mood from check-ins is time-weighted (gaps capped at 6 hours)."),
                L("unrecorded для таблеток — день без отметки, не notTaken.", "support status unrecorded is a day with no mark, not notTaken."),
                L("Superseded-сон хранится в списке, но не входит в итоги.", "Superseded sleep is listed but excluded from totals."),
                L("Совпадение по времени не означает причину.", "Co-occurrence is not causation.")
            ]
        )
    }

    func mapCheckIn(_ checkIn: CheckIn) -> ExportCheckIn {
        ExportCheckIn(
            id: checkIn.id.uuidString,
            eventTime: clock.instant(checkIn.timestamp),
            recordedAt: clock.instant(checkIn.createdAt),
            updatedAt: clock.instant(checkIn.updatedAt),
            mood: ExportMap.mood(checkIn.mood),
            energy: checkIn.energy.map(ExportMap.energy),
            motivation: checkIn.motivation.map(ExportMap.motivation),
            moodReason: options.includeNotes ? checkIn.reason.map(Ldata) : checkIn.reason.map(Ldata),
            motivationReason: checkIn.motivationReason.map(Ldata),
            note: options.includeNotes ? checkIn.note : nil,
            origin: checkIn.origin.rawValue,
            scheduledAt: checkIn.scheduledAt.map(clock.instant),
            sourceIdentifier: checkIn.sourceIdentifier,
            occurrenceId: checkIn.occurrenceID,
            sessionId: checkIn.session?.id.uuidString,
            sessionActivity: checkIn.session.map { Ldata($0.activity) },
            sessionType: checkIn.session.map { ExportMap.sessionType($0.sessionType) },
            conditionSnapshot: checkIn.conditionSnapshot.map(ExportMap.condition)
        )
    }

    func mapEmotion(_ entry: EmotionEntry) -> ExportEmotionEntry {
        ExportEmotionEntry(
            id: entry.id.uuidString,
            eventTime: clock.instant(entry.eventDate),
            recordedAt: clock.instant(entry.createdAt),
            updatedAt: clock.instant(entry.updatedAt),
            emotions: entry.emotions.map(ExportMap.emotion),
            note: options.includeNotes ? entry.note : nil
        )
    }

    func mapHunger(_ entry: HungerEntry) -> ExportHungerEntry {
        ExportHungerEntry(
            id: entry.id.uuidString,
            eventTime: clock.instant(entry.eventDate),
            recordedAt: clock.instant(entry.createdAt),
            updatedAt: clock.instant(entry.updatedAt),
            hunger: entry.hunger.map(ExportMap.hunger),
            appetite: entry.appetite.map(ExportMap.appetite),
            note: options.includeNotes ? entry.note : nil
        )
    }

    func mapFood(_ entry: FoodEntry, hunger: [HungerEntry]) -> ExportFoodEntry {
        let linked = AnalyticsService.hungerEntry(before: entry.eventDate, in: hunger)
        return ExportFoodEntry(
            id: entry.id.uuidString,
            eventTime: clock.instant(entry.eventDate),
            recordedAt: clock.instant(entry.createdAt),
            updatedAt: clock.instant(entry.updatedAt),
            category: ExportMap.labeled(entry.category.rawValue, entry.category.label, emoji: entry.category.emoji),
            description: entry.desc,
            mealDensity: entry.mealDensity.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            taste: entry.taste.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            treatType: entry.treatType.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            treatAmount: entry.treatAmount.map { ExportMap.labeled($0.rawValue, $0.label) },
            fullness: entry.fullness.map(ExportMap.fullness),
            note: options.includeNotes ? entry.note : nil,
            hungerBefore: linked?.hunger.map(ExportMap.hunger),
            hungerBeforeSeconds: linked.map { entry.eventDate.timeIntervalSince($0.eventDate) },
            hungerBeforeId: linked.map { $0.id.uuidString }
        )
    }

    func mapImpulse(_ entry: ImpulseEntry) -> ExportImpulseEntry {
        ExportImpulseEntry(
            id: entry.id.uuidString,
            eventTime: clock.instant(entry.eventDate),
            recordedAt: clock.instant(entry.createdAt),
            updatedAt: clock.instant(entry.updatedAt),
            category: ExportMap.labeled(entry.category.rawValue, entry.category.label, emoji: entry.category.emoji),
            strength: entry.strength.map(ExportMap.strength),
            outcome: entry.outcome.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            note: options.includeNotes ? entry.note : nil
        )
    }

    func mapConditionEvent(_ event: ConditionEvent) -> ExportConditionEvent {
        ExportConditionEvent(
            id: event.id.uuidString,
            eventTime: clock.instant(event.timestamp),
            recordedAt: clock.instant(event.createdAt),
            updatedAt: clock.instant(event.updatedAt),
            categoryId: event.categoryID.uuidString,
            categoryRaw: Ldata(event.categoryName),
            optionId: event.optionID.uuidString,
            optionRaw: Ldata(event.optionName),
            icon: event.categoryIcon,
            iconImageName: event.optionIconImageName ?? event.categoryIconImageName,
            sessionId: event.session?.id.uuidString
        )
    }

    func mapSession(_ session: FocusSession, checkIns: [CheckIn]) -> ExportSession {
        let end = session.endDate
        let effectiveEnd = end ?? now
        let segments = (session.segments ?? []).sorted { $0.startDate < $1.startDate }.map { segment -> ExportSegment in
            let segmentEnd = segment.endDate ?? now
            return ExportSegment(
                id: segment.id.uuidString,
                type: segment.type.rawValue,
                start: clock.instant(segment.startDate),
                end: segment.endDate.map(clock.instant),
                durationSeconds: segment.duration(asOf: now),
                durationWithinRequestedPeriodSeconds: clipped(segment.startDate, segmentEnd)
            )
        }
        return ExportSession(
            id: session.id.uuidString,
            state: session.state.rawValue,
            activity: Ldata(session.activity),
            type: ExportMap.sessionType(session.sessionType),
            start: clock.instant(session.startDate),
            end: end.map(clock.instant),
            calculatedThrough: end == nil ? clock.instant(now) : nil,
            overlapDurationSeconds: clipped(session.startDate, effectiveEnd),
            activeDurationSeconds: session.activeWorkDuration(asOf: now),
            breakDurationSeconds: session.breakDuration(asOf: now),
            totalDurationSeconds: session.totalDuration(asOf: now),
            breakCount: session.numberOfBreaks,
            origin: session.origin.rawValue,
            checkInIntervalMinutes: session.checkInIntervalMinutes,
            note: options.includeNotes ? session.note : nil,
            recordedAt: clock.instant(session.createdAt),
            updatedAt: clock.instant(session.updatedAt),
            segments: segments,
            conditionChanges: (session.conditionEvents ?? []).sorted { $0.timestamp < $1.timestamp }.map(mapConditionEvent),
            checkInIds: checkIns.filter { $0.session?.id == session.id }.map { $0.id.uuidString },
            integration: session.sourceTaskID.map {
                ExportSessionIntegration(
                    sourceApp: session.sourceApp,
                    sourceTaskId: $0.uuidString,
                    sourceTaskTitle: session.sourceTaskTitle
                )
            }
        )
    }

    func mapSupport(_ entry: SupportEntry) -> ExportSupportEntry {
        ExportSupportEntry(
            id: entry.id.uuidString,
            trackerKey: entry.trackerKey,
            day: clock.dayString(entry.day),
            time: entry.time.map(clock.instant),
            status: ExportMap.labeled(entry.status.rawValue, entry.status.label, glyph: entry.status.glyph),
            note: options.includeNotes ? entry.note : nil,
            recordedAt: clock.instant(entry.createdAt),
            updatedAt: clock.instant(entry.updatedAt),
            source: SleepSource.manual.rawValue
        )
    }

    func mapHealthMed(_ entry: ExportHealthMedCapture) -> ExportHealthMedicationDay {
        ExportHealthMedicationDay(
            day: clock.dayString(entry.day),
            takenCount: entry.takenCount,
            skippedCount: entry.skippedCount,
            status: entry.status.map { ExportMap.labeled($0.rawValue, $0.label, glyph: $0.glyph) },
            detail: entry.detail,
            sourceName: entry.sourceName
        )
    }

    func mapCycle(_ entry: CycleEntry) -> ExportCycleEntry {
        ExportCycleEntry(
            id: entry.id.uuidString,
            day: clock.dayString(entry.date),
            kind: ExportMap.labeled(entry.kind.rawValue, entry.kind.label, emoji: entry.kind.icon),
            note: options.includeNotes ? entry.note : nil,
            recordedAt: clock.instant(entry.createdAt),
            updatedAt: clock.instant(entry.updatedAt)
        )
    }

    func mapHealthCycle(_ entry: ExportHealthCycleCapture) -> ExportHealthCycleMark {
        ExportHealthCycleMark(
            day: clock.dayString(entry.day),
            kind: ExportMap.labeled(entry.kind.rawValue, entry.kind.label, emoji: entry.kind.icon),
            flow: entry.flow.map { ExportMap.labeled("\($0.rawValue)", $0.label) },
            isCycleStart: entry.isCycleStart,
            sourceName: entry.sourceName
        )
    }

    func mapNote(_ note: JournalNote) -> ExportNote {
        ExportNote(
            id: note.id.uuidString,
            eventTime: clock.instant(note.timestamp),
            recordedAt: clock.instant(note.createdAt),
            updatedAt: clock.instant(note.updatedAt),
            text: note.text
        )
    }

    func mapSleep(_ sleep: SleepSessionSummary) -> ExportSleep {
        ExportSleep(
            id: sleep.id,
            day: clock.dayString(sleep.day),
            kind: ExportMap.labeled(sleep.kind.rawValue, sleep.kind.label, emoji: sleep.kind.emoji),
            source: sleep.source.rawValue,
            start: clock.instant(sleep.start),
            end: clock.instant(sleep.end),
            totalSleepSeconds: sleep.totalSleep,
            timeInBedSeconds: sleep.timeInBed,
            awakeDurationSeconds: sleep.awake,
            coreDurationSeconds: sleep.duration(of: .core),
            deepDurationSeconds: sleep.duration(of: .deep),
            remDurationSeconds: sleep.duration(of: .rem),
            unspecifiedDurationSeconds: sleep.duration(of: .unspecified),
            awakeningCount: sleep.awakeningCount,
            sourceName: sleep.sourceName,
            sourceBundleIdentifier: sleep.sourceBundleIdentifier,
            productType: sleep.productType,
            subjectiveQuality: sleep.quality.map(ExportMap.quality),
            note: options.includeNotes ? sleep.note : nil,
            isSuperseded: sleep.isSuperseded,
            supersededBy: sleep.supersededBy?.rawValue,
            countedInTotals: !sleep.isSuperseded,
            intervals: sleep.intervals.map {
                ExportSleepInterval(
                    stage: $0.stage.rawValue,
                    stageLabel: $0.stage.label,
                    start: clock.instant($0.start),
                    end: clock.instant($0.end),
                    durationSeconds: $0.duration
                )
            }
        )
    }

    func mapDay(
        _ day: Date,
        checkIns: [CheckIn],
        sessions: [FocusSession],
        emotions: [EmotionEntry],
        hunger: [HungerEntry],
        food: [FoodEntry],
        impulses: [ImpulseEntry],
        notes: [JournalNote],
        standalone: [ConditionEvent],
        sleep: [SleepSessionSummary],
        cycleEntries: [CycleEntry],
        supportEntries: [SupportEntry],
        healthMarks: [CycleMark],
        healthCycle: [ExportHealthCycleCapture],
        healthMedByDay: [Date: ExportHealthMedCapture]
    ) -> ExportDay {
        let dayStart = calendar.startOfDay(for: day)
        let healthRecord = healthMedByDay[dayStart]
        let healthModel: HealthMedicationDay? = healthRecord.map {
            HealthMedicationDay(day: $0.day, takenCount: $0.takenCount, skippedCount: $0.skippedCount, sourceName: $0.sourceName, calendar: calendar)
        }
        let summary = AnalyticsService.dailySummary(
            date: day,
            sessions: sessions,
            checkIns: checkIns,
            cycleEntries: cycleEntries,
            supportEntries: supportEntries,
            notes: notes,
            diaryFactors: standalone,
            foodEntries: food,
            hungerEntries: hunger,
            emotionEntries: emotions,
            impulseEntries: impulses,
            healthCycleMarks: healthMarks,
            healthMedication: healthModel,
            calendar: calendar
        )
        let sleepDay = SleepDaySummary(day: dayStart, sessions: sleep.filter { calendar.isDate($0.day, inSameDayAs: day) })
        let method = L("среднее наблюдений этого дня, без заполнения пропусков", "mean of this day's observations; missing answers stay missing")
        let energyValues = summary.moodPoints.compactMap(\.energy?.scale)
        let motivationValues = summary.moodPoints.compactMap(\.motivation?.scale)
        let healthOnDay = healthCycle.first { calendar.isDate($0.day, inSameDayAs: day) }
        let manualOnDay = cycleEntries.contains { calendar.isDate($0.date, inSameDayAs: day) }
        let cycleSource: String?
        if manualOnDay { cycleSource = "manualOverridesHealth" }
        else if healthOnDay != nil { cycleSource = SleepSource.healthKit.rawValue }
        else if summary.cycleDay != nil || summary.isPeriodDay { cycleSource = "derivedFromRecordedStarts" }
        else { cycleSource = nil }

        let support: ExportDaySupport
        if let marked = summary.support {
            support = ExportDaySupport(
                status: marked.status.rawValue,
                statusLabel: marked.status.label,
                glyph: marked.status.glyph,
                source: marked.source.rawValue,
                entryId: AnalyticsService.supportEntry(on: day, entries: supportEntries, calendar: calendar)?.id.uuidString,
                time: marked.time.map(clock.instant),
                note: options.includeNotes ? marked.note : nil,
                takenCount: marked.source == .healthKit ? healthRecord?.takenCount : nil,
                skippedCount: marked.source == .healthKit ? healthRecord?.skippedCount : nil
            )
        } else {
            support = ExportDaySupport(
                status: "unrecorded",
                statusLabel: L("Не отмечено", "Not recorded"),
                glyph: nil,
                source: nil,
                entryId: nil,
                time: nil,
                note: nil,
                takenCount: nil,
                skippedCount: nil
            )
        }

        let overlappingSleep = sleep.filter { overlapsOnDay($0.start, $0.end, day: day) }
        let overlappingSessions = sessions.filter { overlapsOnDay($0.startDate, $0.endDate ?? now, day: day) }
        let hasData = !summary.isEmpty || summary.isPeriodDay || !sleepDay.sessions.isEmpty || support.status != "unrecorded"

        return ExportDay(
            date: clock.dayString(day),
            hasData: hasData,
            mood: summary.moodStats.average.map { ExportDayScale(average: $0, observationCount: summary.moodStats.checkInCount, method: L("среднее настроения дня, взвешенное по времени между check-in", "time-weighted mean of the day's mood check-ins")) },
            energy: averageScale(energyValues, method: method),
            motivation: averageScale(motivationValues, method: method),
            hunger: averageScale(summary.food.entries.isEmpty ? hunger.filter { calendar.isDate($0.eventDate, inSameDayAs: day) }.compactMap { $0.hunger?.scale } : hunger.filter { calendar.isDate($0.eventDate, inSameDayAs: day) }.compactMap { $0.hunger?.scale }, method: method),
            appetite: averageScale(hunger.filter { calendar.isDate($0.eventDate, inSameDayAs: day) }.compactMap { $0.appetite?.scale }, method: method),
            emotions: summary.distinctEmotions.map { ExportMap.labeled($0.rawValue, $0.label, emoji: $0.emoji) },
            emotionEntryCount: summary.emotions.count,
            mealsByCategory: Dictionary(uniqueKeysWithValues: FoodCategory.allCases.map { cat in
                (cat.rawValue, summary.food.entries.filter { $0.category == cat }.count)
            }.filter { $0.1 > 0 }),
            mealCount: summary.food.entries.count,
            impulseCount: summary.impulses.count,
            impulsesByCategory: countMap(summary.impulses.map(\.category.rawValue)),
            impulsesByOutcome: countMap(summary.impulses.compactMap(\.outcome?.rawValue)),
            impulsesByStrength: countMap(summary.impulses.compactMap(\.strength?.rawValue)),
            nightSleep: sleepDay.nightTotal.map { ExportDaySleep(durationSeconds: $0, sessionIds: sleepDay.countedSessions.filter { $0.kind == .night }.map(\.id)) },
            napSleep: sleepDay.napTotal > 0 ? ExportDaySleep(durationSeconds: sleepDay.napTotal, sessionIds: sleepDay.naps.map(\.id)) : nil,
            sleepQuality: sleepDay.quality.map(ExportMap.quality),
            cycleDay: summary.cycleDay,
            isPeriodDay: summary.isPeriodDay,
            cycleSource: cycleSource,
            menstrualFlow: healthOnDay?.flow.map { ExportMap.labeled("\($0.rawValue)", $0.label) },
            isCycleStart: healthOnDay?.isCycleStart ?? (summary.cycleEvents.contains(.periodStart) ? true : nil),
            support: support,
            sessionDurationByTypeSeconds: Dictionary(uniqueKeysWithValues: summary.sessionTypes.map { ($0.type?.rawValue ?? "unassigned", $0.activeDuration) }),
            sessionCountByType: Dictionary(uniqueKeysWithValues: summary.sessionTypes.map { ($0.type?.rawValue ?? "unassigned", $0.sessionCount) }),
            activeDurationSeconds: summary.totalActiveDuration,
            breakDurationSeconds: summary.totalBreakDuration,
            conditions: summary.conditions.map(ExportMap.condition),
            noteIds: summary.notes.map { $0.id.uuidString },
            eventIds: ExportDayEventIDs(
                checkIns: summary.moodPoints.map { $0.id.uuidString },
                emotions: summary.emotions.map { $0.id.uuidString },
                hungerAppetite: hunger.filter { calendar.isDate($0.eventDate, inSameDayAs: day) }.map { $0.id.uuidString },
                food: summary.food.entries.map { $0.id.uuidString },
                impulses: summary.impulses.map { $0.id.uuidString },
                sessions: overlappingSessions.map { $0.id.uuidString },
                sleep: overlappingSleep.map(\.id),
                notes: summary.notes.map { $0.id.uuidString },
                standaloneConditions: standalone.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }.map { $0.id.uuidString }
            )
        )
    }

    func overlapsOnDay(_ start: Date, _ end: Date, day: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return start < dayEnd && end > dayStart
    }

    func averageScale(_ values: [Double], method: String) -> ExportDayScale? {
        guard !values.isEmpty else { return nil }
        return ExportDayScale(average: values.reduce(0, +) / Double(values.count), observationCount: values.count, method: method)
    }

    func countMap(_ keys: [String]) -> [String: Int] {
        Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
    }

    func summarize(
        days: [ExportDay],
        checkIns: [ExportCheckIn],
        sessions: [ExportSession],
        sleep: [ExportSleep]
    ) -> ExportPeriodSummary {
        let dayMethod = L("среднее дневных средних: каждый день с данными имеет вес 1", "mean of daily means: each day with data has weight 1")
        let timeMethod = L("среднее check-in, взвешенное по времени (разрыв не больше 6 часов)", "time-weighted mean of check-ins (gaps capped at 6 hours)")
        let countedSleep = sleep.filter(\.countedInTotals)
        func dayAvg(_ key: (ExportDay) -> ExportDayScale?) -> ExportCountedAverage {
            let present = days.compactMap(key)
            let average = present.isEmpty ? nil : present.map(\.average).reduce(0, +) / Double(present.count)
            return ExportCountedAverage(average: average, dayCount: present.count, observationCount: present.reduce(0) { $0 + $1.observationCount }, method: dayMethod)
        }
        let moodTime: ExportCountedAverage = {
            let values = checkIns.map { (scale: Double($0.mood.value), time: $0.eventTime) }
            _ = values
            let stats = AnalyticsService.moodStatistics(of: input.checkIns.filter { instant($0.timestamp) })
            return ExportCountedAverage(average: stats.average, dayCount: days.filter { $0.mood != nil }.count, observationCount: checkIns.count, method: timeMethod)
        }()
        var supportCounts: [String: Int] = [:]
        for day in days { supportCounts[day.support.status, default: 0] += 1 }
        var meals: [String: Int] = [:]
        for day in days { for (k, v) in day.mealsByCategory { meals[k, default: 0] += v } }
        var emotionCounts: [String: Int] = [:]
        for day in days { for item in day.emotions { emotionCounts[item.raw, default: 0] += 1 } }
        var impulseCat: [String: Int] = [:]
        for day in days { for (k, v) in day.impulsesByCategory { impulseCat[k, default: 0] += v } }
        var sessionTypes: [String: Int] = [:]
        var sessionActivities: [String: Int] = [:]
        for session in sessions {
            sessionTypes[session.type.raw, default: 0] += 1
            sessionActivities[session.activity, default: 0] += 1
        }
        var stages: [String: Double] = [:]
        for night in countedSleep where night.kind.raw == SleepKind.night.rawValue {
            stages["core", default: 0] += night.coreDurationSeconds
            stages["deep", default: 0] += night.deepDurationSeconds
            stages["rem", default: 0] += night.remDurationSeconds
            stages["unspecified", default: 0] += night.unspecifiedDurationSeconds
            stages["awake", default: 0] += night.awakeDurationSeconds
        }
        return ExportPeriodSummary(
            periodDays: days.count,
            emptyDays: days.filter { !$0.hasData }.count,
            daysWithMood: days.filter { $0.mood != nil }.count,
            daysWithSleep: days.filter { $0.nightSleep != nil || $0.napSleep != nil }.count,
            daysWithFood: days.filter { $0.mealCount > 0 }.count,
            daysWithEmotions: days.filter { $0.emotionEntryCount > 0 }.count,
            daysWithImpulses: days.filter { $0.impulseCount > 0 }.count,
            daysWithSessions: days.filter { !$0.eventIds.sessions.isEmpty }.count,
            daysWithPeriod: days.filter(\.isPeriodDay).count,
            checkInCount: checkIns.count,
            emotionEntryCount: days.reduce(0) { $0 + $1.emotionEntryCount },
            hungerEntryCount: days.reduce(0) { $0 + $1.eventIds.hungerAppetite.count },
            foodCount: days.reduce(0) { $0 + $1.mealCount },
            impulseCount: days.reduce(0) { $0 + $1.impulseCount },
            sessionCount: sessions.count,
            sleepCount: sleep.count,
            noteCount: days.reduce(0) { $0 + $1.noteIds.count },
            mood: moodTime,
            energy: dayAvg(\.energy),
            motivation: dayAvg(\.motivation),
            hunger: dayAvg(\.hunger),
            appetite: dayAvg(\.appetite),
            nightSleepSeconds: countedSleep.filter { $0.kind.raw == SleepKind.night.rawValue }.reduce(0) { $0 + $1.totalSleepSeconds },
            napSleepSeconds: countedSleep.filter { $0.kind.raw == SleepKind.nap.rawValue }.reduce(0) { $0 + $1.totalSleepSeconds },
            activeDurationSeconds: sessions.reduce(0) { $0 + $1.activeDurationSeconds },
            breakDurationSeconds: sessions.reduce(0) { $0 + $1.breakDurationSeconds },
            supportDaysByStatus: supportCounts,
            mealsByCategory: meals,
            emotionsByRaw: emotionCounts,
            impulsesByCategory: impulseCat,
            sessionsByType: sessionTypes,
            sessionsByActivity: sessionActivities,
            sleepStagesSeconds: stages
        )
    }
}

// MARK: - Markdown

private enum ExportMarkdown {
    static func render(_ document: MoodPomodoroExport, options: ExportOptions, calendar: Calendar) -> String {
        var lines: [String] = []
        if options.includeAIPrompt {
            lines.append(L(
                "Ниже — полный экспорт моего дневника из приложения Mood Pomodoro. Пожалуйста: 1) ищи повторяющиеся связи между сном, циклом, таблетками, занятиями, эмоциями, едой и импульсивностью; 2) отделяй наблюдение от причинного вывода; 3) учитывай число наблюдений и пропуски; 4) отмечай противоречивые закономерности; 5) не ставь диагноз; 6) сначала перечисли уверенные наблюдения, затем гипотезы для дальнейшего отслеживания. Совпадение по времени не означает причину.",
                "Below is a complete export of my diary from the Mood Pomodoro app. Please: 1) look for repeating links between sleep, cycle, medication, activities, emotions, food and impulsivity; 2) separate observation from causal claims; 3) weigh sample size and missing data; 4) flag contradictory patterns; 5) do not diagnose; 6) list confident observations first, then hypotheses to keep tracking. Co-occurrence is not causation."
            ))
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        let range = "\(document.requestedPeriod.start) – \(document.requestedPeriod.end)"
        lines.append("# " + L("Дневник настроения", "Mood diary") + " · " + range)
        lines.append("_" + L("Экспорт из приложения Mood Pomodoro", "Exported from the Mood Pomodoro app")
                     + ", \(document.exportedAt). "
                     + L("Часовой пояс", "Time zone") + ": \(document.timezone). "
                     + L("Это самонаблюдения, а не медицинские данные.", "These are self-observations, not medical records.") + "_")
        lines.append("")
        if !document.privacy.excludedByToggles.isEmpty {
            lines.append("- " + L("Исключено переключателями", "Excluded by toggles") + ": " + document.privacy.excludedByToggles.joined(separator: ", "))
        }
        lines.append("- " + L("schemaVersion", "schemaVersion") + ": \(document.schemaVersion)")
        lines.append("")

        lines.append("## " + L("Как читать", "How to read this"))
        for rule in document.definitions.rules { lines.append("- " + rule) }
        let moodLegend = document.definitions.mood.map { "\($0.value) \($0.emoji) \($0.label.lowercased())" }.joined(separator: ", ")
        lines.append("- " + L("Настроение — шкала от 1 до 5", "Mood is on a 1–5 scale") + ": \(moodLegend).")
        lines.append("- " + L("Check-in — момент, когда я отметила настроение: во время сессии фокуса (по напоминанию таймера) или сама. Среднее настроение дня и периода взвешено по времени: каждая отметка весит столько, сколько длилась (половина промежутка до предыдущей и до следующей отметки, промежуток больше 6 часов считается за 6 часов), поэтому 3 часа на 5 весят больше, чем час частых низких отметок.", "A check-in is a moment when I recorded my mood — either prompted by a timer during a focus session, or on my own. The average mood for a day or period is weighted by time: each check-in counts for as long as it lasted (half the gap to the previous and to the next check-in; gaps over 6 hours count as 6 hours), so 3 hours at 5 weighs more than an hour of frequent low check-ins."))
        lines.append("- " + L("«Записано позже» — запись сделана задним числом; время в начале строки — когда это было на самом деле.", "“Recorded later” means the entry was added afterwards; the time at the start of the line is when it actually happened."))
        if options.includeSupport {
            lines.append("- " + L("Ежедневная поддержка — моя отметка: принято / не принято / не помню. День без отметки значит «не записано», а не «не принято».", "Daily support is my own mark: taken / not taken / don't remember. A day with no mark means it wasn't recorded — not that it wasn't taken."))
        }
        if options.includeFood {
            lines.append("- " + L("Еда — мои собственные пометки для наблюдений: «полезная / обычная / вредная» — это ярлыки на записях, а не оценка меня и не медицинская классификация. Калории и вес еды не считаются. Голод (насколько телу нужна еда) и аппетит (насколько хочется есть) — две разные шкалы 1–5, они не выводятся одна из другой.", "Food entries are my own labels for observation: “wholesome / regular / junk” tag a record, they are not a judgement of me and not a medical classification. Nothing counts calories or portions. Hunger (how much my body needs food) and appetite (how much I feel like eating) are two separate 1–5 scales and neither is derived from the other."))
        }
        lines.append("- " + L("Цифры по нескольким записям ненадёжны, и то, что два события совпали, не значит, что одно вызвало другое.", "Figures based on a handful of entries aren't reliable, and two things happening together doesn't mean one caused the other."))
        lines.append("")

        lines.append("## " + L("Итоги за период", "Summary"))
        lines += summaryLines(document)
        lines.append("")

        lines.append("## " + L("По дням", "Day by day"))
        let withData = document.days.filter(\.hasData)
        if withData.isEmpty {
            lines.append("")
            lines.append(L("За этот период записей нет.", "No entries in this period."))
        } else {
            for day in withData {
                lines.append("")
                lines += dayBlock(day, document: document, options: options)
            }
        }

        lines.append("")
        lines.append("## " + L("Методика агрегации", "Aggregation method"))
        for rule in document.definitions.rules { lines.append("- " + rule) }
        lines.append("- mood.method: \(document.summary.mood.method)")
        lines.append("- energy.method: \(document.summary.energy.method)")

        lines.append("")
        lines.append("## " + L("Техническая информация", "Technical information"))
        lines.append("- schemaVersion: \(document.schemaVersion)")
        lines.append("- exportedAt: \(document.exportedAt)")
        lines.append("- timezone: \(document.timezone)")
        lines.append("- locale: \(document.locale)")
        lines.append("- range: \(document.requestedPeriod.startInstant) → \(document.requestedPeriod.endExclusive)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func summaryLines(_ document: MoodPomodoroExport) -> [String] {
        var lines: [String] = []
        let s = document.summary
        lines.append("- " + L("Дней в периоде", "Days in period") + ": \(s.periodDays); " + L("с отметками настроения", "with mood entries") + ": \(s.daysWithMood); " + L("полностью пустых", "fully empty") + ": \(s.emptyDays)")
        if let average = s.mood.average {
            lines.append("- " + L("Check-in", "Check-ins") + ": \(s.checkInCount); " + L("среднее настроение", "average mood") + ": " + String(format: "%.1f / 5", average))
            let distribution = document.definitions.mood.map { item -> String in
                let count = document.checkIns.filter { $0.mood.raw == item.raw }.count
                let share = s.checkInCount == 0 ? 0 : Int((Double(count) / Double(s.checkInCount) * 100).rounded())
                return "\(item.emoji) \(share)%"
            }
            lines.append("- " + L("Распределение", "Distribution") + ": " + distribution.joined(separator: " · "))
        } else {
            lines.append("- " + L("Отметок настроения за период нет.", "No mood check-ins in this period."))
        }
        if s.sessionCount > 0 {
            lines.append("- " + L("Время в фокусе", "Focus time") + ": \(DurationFormatting.compact(s.activeDurationSeconds)), " + L("сессий", "sessions") + ": \(s.sessionCount)")
            for (name, count) in s.sessionsByActivity.sorted(by: { $0.key < $1.key }) {
                lines.append("  - \(name) — " + L("сессий", "sessions") + ": \(count)")
            }
        }
        if document.privacy.includeSupport {
            let parts = document.definitions.supportStatuses.map { item in
                "\(item.label.lowercased()) \(s.supportDaysByStatus[item.raw] ?? 0)"
            } + [L("не отмечено", "not recorded") + " \(s.supportDaysByStatus["unrecorded"] ?? 0)"]
            lines.append("- " + L("Ежедневная поддержка, дней", "Daily support, days") + ": " + parts.joined(separator: " · "))
        }
        if document.privacy.includeFood, s.foodCount > 0 {
            let parts = s.mealsByCategory.sorted(by: { $0.key < $1.key }).map { key, count in
                let label = document.definitions.foodCategories.first { $0.raw == key }?.label.lowercased() ?? key
                return "\(label) \(count)"
            }
            lines.append("- " + L("Записей о еде", "Food entries") + ": \(s.foodCount) (" + parts.joined(separator: " · ") + ")")
        }
        if let hunger = s.hunger.average {
            lines.append("- " + L("Голод и аппетит", "Hunger and appetite") + ": " + L("средний голод", "average hunger") + " " + String(format: "%.1f / 5", hunger) + " (\(s.hunger.observationCount))")
        }
        if document.privacy.includeCycle, s.daysWithPeriod > 0 {
            let periodDays = document.days.filter(\.isPeriodDay).map(\.date)
            lines.append("- " + L("Дни менструации", "Period days") + ": " + periodDays.joined(separator: ", "))
        }
        if s.nightSleepSeconds > 0 || s.napSleepSeconds > 0 {
            lines.append("- " + L("Сон", "Sleep") + ": " + L("ночь", "night") + " \(DurationFormatting.compact(s.nightSleepSeconds)); " + L("дневной", "naps") + " \(DurationFormatting.compact(s.napSleepSeconds))")
        }
        if !s.emotionsByRaw.isEmpty {
            let parts = s.emotionsByRaw.sorted(by: { $0.key < $1.key }).map { key, count in
                let label = document.definitions.emotions.first { $0.raw == key }
                return "\(label?.emoji ?? "") \(label?.label ?? key) \(count)"
            }
            lines.append("- " + L("Эмоции", "Emotions") + ": " + parts.joined(separator: " · "))
        }
        if s.impulseCount > 0 {
            lines.append("- " + L("Импульсы", "Impulses") + ": \(s.impulseCount)")
        }
        return lines
    }

    static func dayBlock(_ day: ExportDay, document: MoodPomodoroExport, options: ExportOptions) -> [String] {
        var header = "### " + day.date
        if let mood = day.mood {
            header += " — " + L("среднее", "average") + " " + String(format: "%.1f / 5", mood.average)
                + " (\(mood.observationCount) check-in)"
        }
        var lines = [header]

        if options.includeSupport {
            let support = day.support
            if support.status == "unrecorded" {
                lines.append("- 💊 " + L("Ежедневная поддержка", "Daily support") + ": " + support.statusLabel)
            } else {
                var line = "- 💊 " + L("Ежедневная поддержка", "Daily support") + ": \(support.statusLabel)"
                if let time = support.time { line += " · \(time)" }
                else { line += " · " + L("в течение дня", "during the day") }
                if let note = support.note { line += " — “\(note)”" }
                lines.append(line)
            }
        }
        if options.includeCycle {
            if day.isPeriodDay {
                let text = day.cycleDay.map { L("Менструация — день \($0)", "Period — day \($0)") } ?? L("Менструация", "Period")
                lines.append("- 🌸 " + text)
            } else if let cycleDay = day.cycleDay {
                lines.append("- 🌸 " + L("День цикла: \(cycleDay)", "Cycle day: \(cycleDay)"))
            }
        }
        if day.activeDurationSeconds > 0 {
            lines.append("- 📚 " + L("Занятия", "Focus") + ": " + DurationFormatting.compact(day.activeDurationSeconds))
        }
        if !day.conditions.isEmpty {
            let parts = day.conditions.map { "\($0.categoryRaw): \($0.optionRaw)" }
            lines.append("- ☕ " + L("Условия", "Conditions") + ": " + parts.joined(separator: "; "))
        }
        if let night = day.nightSleep {
            lines.append("- 🌙 " + L("Ночной сон", "Night sleep") + ": " + DurationFormatting.compact(night.durationSeconds))
        }
        if let nap = day.napSleep {
            lines.append("- 😴 " + L("Дневной сон", "Nap") + ": " + DurationFormatting.compact(nap.durationSeconds))
        }

        var events: [(String, String)] = []
        func stamp(_ iso: String) -> String { String(iso.dropFirst(11).prefix(8)) }

        for id in day.eventIds.checkIns {
            guard let item = document.checkIns.first(where: { $0.id == id }) else { continue }
            var text = "\(item.mood.emoji) \(item.mood.label) (\(item.mood.value)/5)"
            if let reason = item.moodReason { text += " — \(reason)" }
            if let energy = item.energy { text += " · " + L("силы", "energy") + ": \(energy.emoji) \(energy.label)" }
            if let motivation = item.motivation {
                text += " · " + L("мотивация", "motivation") + ": \(motivation.emoji) \(motivation.label)"
                if let why = item.motivationReason { text += " (\(why))" }
            }
            if let note = item.note, !note.isEmpty { text += " — “\(note)”" }
            events.append((item.eventTime, text))
        }
        if options.includeFood {
            for id in day.eventIds.food {
                guard let item = document.food.first(where: { $0.id == id }) else { continue }
                var text = "\(item.category.emoji ?? "") \(item.category.label)"
                if let density = item.mealDensity { text += " · \(density.label)" }
                if let taste = item.taste { text += " · \(taste.label)" }
                if let treat = item.treatType { text += " · \(treat.label)" }
                if let amount = item.treatAmount { text += " · \(amount.label)" }
                if let desc = item.description, !desc.isEmpty { text += " — \(desc)" }
                if let fullness = item.fullness { text += " · " + L("после еды", "afterwards") + ": \(fullness.label)" }
                if let note = item.note, !note.isEmpty { text += " — “\(note)”" }
                events.append((item.eventTime, text))
            }
            for id in day.eventIds.hungerAppetite {
                guard let item = document.hungerAppetite.first(where: { $0.id == id }) else { continue }
                var parts: [String] = []
                if let hunger = item.hunger { parts.append(L("Голод: \(hunger.value)/5", "Hunger: \(hunger.value)/5")) }
                if let appetite = item.appetite { parts.append(L("Аппетит: \(appetite.value)/5", "Appetite: \(appetite.value)/5")) }
                var text = "🍎 " + parts.joined(separator: " · ")
                if let note = item.note, !note.isEmpty { text += " — “\(note)”" }
                events.append((item.eventTime, text))
            }
        }
        for id in day.eventIds.emotions {
            guard let item = document.emotions.first(where: { $0.id == id }) else { continue }
            let names = item.emotions.map { "\($0.emoji) \($0.label)" }.joined(separator: " · ")
            var text = names
            if let note = item.note, options.includeNotes { text += " · \(note)" }
            events.append((item.eventTime, text))
        }
        for id in day.eventIds.impulses {
            guard let item = document.impulses.first(where: { $0.id == id }) else { continue }
            var text = "\(item.category.emoji ?? "") \(item.category.label)"
            if let outcome = item.outcome { text += " · \(outcome.label)" }
            if let strength = item.strength { text += " · " + L("сила: \(strength.label.lowercased())", "strength: \(strength.label.lowercased())") }
            events.append((item.eventTime, text))
        }
        if options.includeNotes {
            for id in day.eventIds.notes {
                guard let item = document.notes.first(where: { $0.id == id }) else { continue }
                events.append((item.eventTime, "📝 “\(item.text)”"))
            }
        }
        for id in day.eventIds.sessions {
            guard let item = document.sessions.first(where: { $0.id == id }) else { continue }
            var text = "▶︎ \(item.activity) · \(item.type.label)"
            text += " · \(item.start) – \(item.end ?? "…")"
            if item.end == nil, let through = item.calculatedThrough {
                text += " " + L("(активна на момент экспорта \(through))", "(active as of export \(through))")
            }
            if let link = item.integration {
                text += " · " + L("задача", "task") + ": \(link.sourceTaskTitle ?? link.sourceTaskId)"
            }
            events.append((item.start, text))
            for segment in item.segments {
                let glyph = segment.type == "pause" ? "🌿" : "▶︎"
                events.append((segment.start, "\(glyph) \(segment.type) · \(segment.start) – \(segment.end ?? "…")"))
            }
        }
        for id in day.eventIds.sleep {
            guard let item = document.sleep.first(where: { $0.id == id }) else { continue }
            var text = "\(item.kind.emoji ?? "") \(item.kind.label) · \(item.start) – \(item.end) · " + DurationFormatting.compact(item.totalSleepSeconds)
            if item.isSuperseded { text += " " + L("(не входит в итоги, перекрыта)", "(excluded from totals, superseded)") }
            if let quality = item.subjectiveQuality { text += " · \(quality.label)" }
            if let note = item.note, options.includeNotes { text += " — “\(note)”" }
            events.append((item.start, text))
        }
        for id in day.eventIds.standaloneConditions {
            guard let item = document.standaloneConditions.first(where: { $0.id == id }) else { continue }
            events.append((item.eventTime, "☕ \(item.categoryRaw): \(item.optionRaw)"))
        }

        events.sort { $0.0 < $1.0 }
        for (time, text) in events {
            let display: String
            if time.count >= 19, time.contains("T") {
                let dayPart = String(time.prefix(10))
                let clockPart = String(time.dropFirst(11).prefix(8))
                display = dayPart == day.date ? clockPart : "\(dayPart) \(clockPart)"
            } else {
                display = time
            }
            lines.append("- \(display) · \(text)")
        }
        return lines
    }
}
