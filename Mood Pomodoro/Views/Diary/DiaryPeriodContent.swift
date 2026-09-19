import SwiftUI
import SwiftData

/// Period-scoped diary body: queries only the visible interval (plus a pad
/// for sessions/sleep that started the night before), builds the timeline
/// snapshot off the main actor, and caches day/month summaries so pan/zoom
/// and chip toggles do not walk SwiftData again.
struct DiaryPeriodContent: View {
    let selectedDate: Date
    let isDayMode: Bool
    let isWide: Bool
    let isToday: Bool
    @Binding var timelineSpan: TimelineSpan
    @Binding var tappedDay: Date?
    let onQuickMood: () -> Void
    let onAdd: (DiaryEntrySheet) -> Void
    let onEdit: (DiaryEditTarget, Date) -> Void
    let onSelectDay: (Date) -> Void
    /// Swiping the chart past its edge asks the diary to move on a period.
    let onStep: (Int) -> Void

    @Environment(SleepStore.self) private var sleepStore

    @Query private var sessions: [FocusSession]
    @Query private var checkIns: [CheckIn]
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]
    @Query private var cycleEntries: [CycleEntry]
    @Query private var supportEntries: [SupportEntry]
    @Query private var notes: [JournalNote]
    @Query private var conditionEvents: [ConditionEvent]
    @Query private var foodEntries: [FoodEntry]
    @Query private var hungerEntries: [HungerEntry]
    @Query private var emotionEntries: [EmotionEntry]
    @Query private var impulseEntries: [ImpulseEntry]

    @State private var snapshot = TimelineSnapshot.empty
    @State private var daily: DailySummary?
    @State private var monthly: MonthlySummary?
    @State private var buildGeneration = 0

    private let calendar = Calendar.current

    init(
        selectedDate: Date,
        isDayMode: Bool,
        isWide: Bool,
        isToday: Bool,
        timelineSpan: Binding<TimelineSpan>,
        tappedDay: Binding<Date?>,
        onQuickMood: @escaping () -> Void,
        onAdd: @escaping (DiaryEntrySheet) -> Void,
        onEdit: @escaping (DiaryEditTarget, Date) -> Void,
        onSelectDay: @escaping (Date) -> Void,
        onStep: @escaping (Int) -> Void
    ) {
        self.selectedDate = selectedDate
        self.isDayMode = isDayMode
        self.isWide = isWide
        self.isToday = isToday
        self._timelineSpan = timelineSpan
        self._tappedDay = tappedDay
        self.onQuickMood = onQuickMood
        self.onAdd = onAdd
        self.onEdit = onEdit
        self.onStep = onStep
        self.onSelectDay = onSelectDay

        let span = timelineSpan.wrappedValue
        let fetch = DiaryPeriodInterval.fetch(for: selectedDate, span: span)
        let cycle = DiaryPeriodInterval.cycleFetch(for: selectedDate, span: span)
        let start = fetch.start
        let end = fetch.end
        let cycleStart = cycle.start

        _sessions = Query(filter: #Predicate<FocusSession> { $0.startDate < end && $0.startDate >= start })
        _checkIns = Query(filter: #Predicate<CheckIn> { $0.timestamp >= start && $0.timestamp < end })
        _cycleEntries = Query(
            filter: #Predicate<CycleEntry> { $0.date >= cycleStart && $0.date < end },
            sort: \CycleEntry.date,
            order: .reverse
        )
        _supportEntries = Query(filter: #Predicate<SupportEntry> { $0.day >= start && $0.day < end })
        _notes = Query(filter: #Predicate<JournalNote> { $0.timestamp >= start && $0.timestamp < end })
        _conditionEvents = Query(filter: #Predicate<ConditionEvent> { $0.timestamp >= start && $0.timestamp < end })
        _foodEntries = Query(filter: #Predicate<FoodEntry> { $0.eventDate >= start && $0.eventDate < end })
        _hungerEntries = Query(filter: #Predicate<HungerEntry> { $0.eventDate >= start && $0.eventDate < end })
        _emotionEntries = Query(filter: #Predicate<EmotionEntry> { $0.eventDate >= start && $0.eventDate < end })
        _impulseEntries = Query(filter: #Predicate<ImpulseEntry> { $0.eventDate >= start && $0.eventDate < end })
    }

    private var isAllTime: Bool { timelineSpan == .all }

    private var visibleInterval: DateInterval {
        let interval = DiaryPeriodInterval.visible(for: selectedDate, span: timelineSpan, calendar: calendar)
        guard isAllTime else { return interval }
        // From the first day anything was recorded, so the chart opens on
        // the whole history rather than on years of nothing before it.
        let dates: [Date?] = [
            checkIns.map(\.timestamp).min(),
            sessions.map(\.startDate).min(),
            foodEntries.map(\.eventDate).min(),
            hungerEntries.map(\.eventDate).min(),
            emotionEntries.map(\.eventDate).min(),
            impulseEntries.map(\.eventDate).min(),
            notes.map(\.timestamp).min(),
            supportEntries.map(\.day).min(),
            cycleEntries.map(\.date).min(),
            sleepStore.sessions.map(\.start).min()
        ]
        let first = dates.compactMap { $0 }.min() ?? .now
        return DateInterval(start: calendar.startOfDay(for: first), end: interval.end)
    }

    private var dataStamp: String {
        "\(timelineSpan.rawValue)|\(visibleInterval.start.timeIntervalSince1970)|\(checkIns.count)|\(sessions.count)|\(foodEntries.count)|\(hungerEntries.count)|\(emotionEntries.count)|\(impulseEntries.count)|\(supportEntries.count)|\(cycleEntries.count)|\(notes.count)|\(sleepStore.sessions.count)|\(sleepStore.cycleMarks.count)|\(sleepStore.medicationDays.count)|\(sleepStore.medicationDays.values.reduce(0) { $0 + $1.takenCount * 100 + $1.skippedCount })"
    }

    var body: some View {
        VStack(spacing: 16) {
            UnifiedTimeline(
                date: selectedDate,
                snapshot: snapshot,
                span: $timelineSpan,
                tappedDay: $tappedDay,
                onSelectDay: onSelectDay,
                onStep: onStep,
                onEdit: onEdit
            )

            if isDayMode {
                DiaryDayView(
                    summary: daily ?? .emptyPlaceholder(date: selectedDate),
                    sleep: sleepStore.daySummary(for: selectedDate, calendar: calendar),
                    isToday: isToday,
                    onQuickMood: onQuickMood,
                    onAdd: onAdd,
                    onEdit: { onEdit($0, selectedDate) }
                )
            } else {
                DiaryMonthView(
                    summary: monthly ?? MonthlySummary.emptyPlaceholder(month: selectedDate),
                    sleep: sleepStore.sessions(in: visibleInterval),
                    isAllTime: isAllTime,
                    emotionEntries: emotionEntries
                        .filter { !$0.isEmpty && visibleInterval.contains($0.eventDate) }
                        .sorted { $0.eventDate > $1.eventDate },
                    emotionContext: emotionContext(at:),
                    isWide: isWide,
                    onSelectDay: onSelectDay
                )
            }
        }
        .task(id: dataStamp) {
            await rebuild()
        }
    }

    @MainActor
    private func rebuild() async {
        buildGeneration += 1
        let generation = buildGeneration
        let interval = visibleInterval

        let dailySummary = PerfSignpost.interval("daily.summary") {
            AnalyticsService.dailySummary(
                date: selectedDate,
                sessions: sessions,
                checkIns: checkIns,
                cycleEntries: cycleEntries,
                supportEntries: supportEntries,
                notes: notes,
                diaryFactors: conditionEvents,
                foodEntries: foodEntries,
                hungerEntries: hungerEntries,
                emotionEntries: emotionEntries,
                impulseEntries: impulseEntries,
                healthCycleMarks: sleepStore.cycleMarks,
                healthMedication: sleepStore.medicationDay(for: selectedDate, calendar: calendar),
                calendar: calendar
            )
        }
        let monthlySummary: MonthlySummary? = isDayMode ? nil : PerfSignpost.interval("monthly.summary") {
            AnalyticsService.periodSummary(
                in: isAllTime ? interval : (calendar.dateInterval(of: .month, for: selectedDate) ?? interval),
                sessions: sessions,
                checkIns: checkIns,
                categories: categories,
                cycleEntries: cycleEntries,
                supportEntries: supportEntries,
                foodEntries: foodEntries,
                hungerEntries: hungerEntries,
                emotionEntries: emotionEntries,
                impulseEntries: impulseEntries,
                healthCycleMarks: sleepStore.cycleMarks,
                healthMedication: sleepStore.medicationDays,
                calendar: calendar
            )
        }
        let contextDays = PerfSignpost.interval("day.aggregates") {
            AnalyticsService.dayAggregates(
                in: interval,
                checkIns: checkIns,
                sessions: sessions,
                hungerEntries: hungerEntries,
                foodEntries: foodEntries,
                emotionEntries: emotionEntries,
                impulseEntries: impulseEntries,
                supportEntries: supportEntries,
                cycleMarks: cycleEntries.map(\.mark) + sleepStore.cycleMarks,
                healthMedication: sleepStore.medicationDays,
                sleepSessions: sleepStore.sessions,
                calendar: calendar
            )
        }

        let facts = TimelineSnapshotBuilder.capture(
            interval: interval,
            checkIns: checkIns,
            hunger: hungerEntries,
            food: foodEntries,
            emotions: emotionEntries,
            impulses: impulseEntries,
            sessions: sessions,
            sleep: sleepStore.sessions
        )

        let span = timelineSpan
        let builtMarks = await Task.detached(priority: .userInitiated) {
            TimelineSnapshotBuilder.build(facts: facts, span: span)
        }.value

        guard generation == buildGeneration else { return }
        snapshot = TimelineSnapshot(
            intervalStart: builtMarks.intervalStart,
            intervalEnd: builtMarks.intervalEnd,
            marks: builtMarks.marks,
            numericGroups: builtMarks.numericGroups,
            dailyAverages: builtMarks.dailyAverages,
            sleepDays: builtMarks.sleepDays,
            contextDays: contextDays
        )
        daily = dailySummary
        if let monthlySummary { monthly = monthlySummary }
    }
}

extension DiaryPeriodContent {
    /// What else was recorded around a feeling — the activity under way, a
    /// check-in, a meal, an impulse, a note — so a look back at when it
    /// happened has something to go on. It lists what sat close in time and
    /// says nothing about what caused what.
    func emotionContext(at date: Date) -> [String] {
        var lines: [String] = []
        let near: TimeInterval = 2 * 3600

        for session in sessions {
            let segments = (session.segments ?? []).filter { $0.type == .work }
            if segments.contains(where: { $0.startDate <= date && ($0.endDate ?? .now) >= date }) {
                lines.append("🌿 " + L("Шло занятие: ", "Activity under way: ") + Ldata(session.activity))
                break
            }
            if segments.contains(where: { ($0.endDate ?? .now) < date && date.timeIntervalSince(($0.endDate ?? .now)) <= 30 * 60 }) {
                lines.append("🌿 " + L("Перед этим — занятие: ", "Just before — activity: ") + Ldata(session.activity))
                break
            }
        }
        if let checkIn = checkIns
            .filter({ abs($0.timestamp.timeIntervalSince(date)) <= 3600 })
            .min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }) {
            var line = "🙂 " + L("Настроение: ", "Mood: ") + checkIn.mood.label + " · " + DateFormatting.time(checkIn.timestamp)
            if let reason = checkIn.reason, !reason.isEmpty { line += " · " + reason }
            lines.append(line)
            if let note = checkIn.note, !note.isEmpty { lines.append("📝 " + note) }
        }
        for food in foodEntries where abs(food.eventDate.timeIntervalSince(date)) <= near {
            lines.append("🍽 " + food.category.label + " · " + DateFormatting.time(food.eventDate))
        }
        for impulse in impulseEntries where abs(impulse.eventDate.timeIntervalSince(date)) <= near {
            lines.append("⚡ " + impulse.category.label + " · " + DateFormatting.time(impulse.eventDate))
        }
        for note in notes where abs(note.timestamp.timeIntervalSince(date)) <= near && !note.text.isEmpty {
            lines.append("📝 " + String(note.text.prefix(160)) + " · " + DateFormatting.time(note.timestamp))
        }
        return lines
    }
}

private extension DailySummary {
    /// Empty stand-in so the day cards can render while the first snapshot builds.
    static func emptyPlaceholder(date: Date) -> DailySummary {
        AnalyticsService.dailySummary(date: date, sessions: [], checkIns: [])
    }
}

private extension MonthlySummary {
    static func emptyPlaceholder(month: Date) -> MonthlySummary {
        AnalyticsService.monthlySummary(month: month, sessions: [], checkIns: [], categories: [])
    }
}
