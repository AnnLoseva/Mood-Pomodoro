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
    let onQuickMood: () -> Void
    let onAdd: (DiaryEntrySheet) -> Void
    let onEdit: (DiaryEditTarget, Date) -> Void
    let onSelectDay: (Date) -> Void

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
        onQuickMood: @escaping () -> Void,
        onAdd: @escaping (DiaryEntrySheet) -> Void,
        onEdit: @escaping (DiaryEditTarget, Date) -> Void,
        onSelectDay: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.isDayMode = isDayMode
        self.isWide = isWide
        self.isToday = isToday
        self._timelineSpan = timelineSpan
        self.onQuickMood = onQuickMood
        self.onAdd = onAdd
        self.onEdit = onEdit
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

    private var visibleInterval: DateInterval {
        DiaryPeriodInterval.visible(for: selectedDate, span: timelineSpan, calendar: calendar)
    }

    private var dataStamp: String {
        "\(timelineSpan.rawValue)|\(visibleInterval.start.timeIntervalSince1970)|\(checkIns.count)|\(sessions.count)|\(foodEntries.count)|\(hungerEntries.count)|\(emotionEntries.count)|\(impulseEntries.count)|\(supportEntries.count)|\(cycleEntries.count)|\(notes.count)|\(sleepStore.sessions.count)|\(sleepStore.cycleMarks.count)|\(sleepStore.medicationDays.count)"
    }

    var body: some View {
        VStack(spacing: 16) {
            UnifiedTimeline(
                date: selectedDate,
                snapshot: snapshot,
                span: $timelineSpan,
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
            AnalyticsService.monthlySummary(
                month: selectedDate,
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
            contextDays: contextDays
        )
        daily = dailySummary
        if let monthlySummary { monthly = monthlySummary }
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
