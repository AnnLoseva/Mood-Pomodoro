import SwiftUI
import SwiftData

/// Everything the diary holds for one day, each record openable — the end of
/// the path "average → day → record". Rows are the diary's own timeline
/// events, so a check-in opens the check-in form, a meal the meal form, a
/// session its details; nothing here is a copy of the data.
struct DayRecordsView: View {
    let day: Date
    @Bindable var store: AnalyticsStore

    @Environment(SleepStore.self) private var sleepStore
    @Environment(AppTabs.self) private var tabs

    @Query private var sessions: [FocusSession]
    @Query private var checkIns: [CheckIn]
    @Query private var notes: [JournalNote]
    @Query private var conditionEvents: [ConditionEvent]
    @Query private var foodEntries: [FoodEntry]
    @Query private var hungerEntries: [HungerEntry]
    @Query private var emotionEntries: [EmotionEntry]
    @Query private var impulseEntries: [ImpulseEntry]
    @Query private var cycleEntries: [CycleEntry]
    @Query private var supportEntries: [SupportEntry]

    @State private var entrySheet: DiaryEntrySheet?

    init(day: Date, store: AnalyticsStore) {
        self.day = day
        self.store = store
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        // A session that began the evening before can still be running today.
        let sessionStart = start.addingTimeInterval(-36 * 3600)
        _sessions = Query(filter: #Predicate<FocusSession> { $0.startDate >= sessionStart && $0.startDate < end })
        _checkIns = Query(filter: #Predicate<CheckIn> { $0.timestamp >= start && $0.timestamp < end })
        _notes = Query(filter: #Predicate<JournalNote> { $0.timestamp >= start && $0.timestamp < end })
        _conditionEvents = Query(filter: #Predicate<ConditionEvent> { $0.timestamp >= start && $0.timestamp < end })
        _foodEntries = Query(filter: #Predicate<FoodEntry> { $0.eventDate >= start && $0.eventDate < end })
        _hungerEntries = Query(filter: #Predicate<HungerEntry> { $0.eventDate >= start && $0.eventDate < end })
        _emotionEntries = Query(filter: #Predicate<EmotionEntry> { $0.eventDate >= start && $0.eventDate < end })
        _impulseEntries = Query(filter: #Predicate<ImpulseEntry> { $0.eventDate >= start && $0.eventDate < end })
        _cycleEntries = Query(filter: #Predicate<CycleEntry> { $0.date >= start && $0.date < end })
        _supportEntries = Query(filter: #Predicate<SupportEntry> { $0.day >= start && $0.day < end })
    }

    private var summary: DailySummary {
        AnalyticsService.dailySummary(
            date: day,
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
            healthMedication: sleepStore.medicationDay(for: day)
        )
    }

    var body: some View {
        let events = summary.timelineEvents
        let nights = sleepStore.daySummary(for: day).sessions
        AnalyticsDetailScaffold(title: DateFormatting.historySectionTitle(day), store: store, showsPeriod: false) {
            if events.isEmpty && nights.isEmpty {
                AnalyticsQuietNote(text: L("За этот день записей нет.", "Nothing recorded on this day."))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(nights) { night in
                        Button { entrySheet = .sleep(editing: night.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(DateFormatting.time(night.start))
                                    .font(.lora(14).monospacedDigit())
                                    .foregroundStyle(AppTheme.inkSoft)
                                    .frame(width: 52, alignment: .leading)
                                Text(night.kind.emoji).font(.system(size: 16)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(night.kind.label) · \(DurationFormatting.compact(night.totalSleep))")
                                        .font(.lora(15))
                                        .foregroundStyle(AppTheme.ink)
                                    if let quality = night.quality {
                                        Text(quality.label).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(events) { event in
                        recordRow(event)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .parchmentCard(padding: 0)
            }

            Button(L("Открыть день в дневнике", "Open this day in the diary")) {
                tabs.openDiary(day: day)
            }
            .buttonStyle(AnalyticsSmallButtonStyle())
        }
        .sheet(item: $entrySheet) { sheet in
            DiaryEntrySheetView(sheet: sheet, day: day)
        }
    }

    @ViewBuilder
    private func recordRow(_ event: TimelineEvent) -> some View {
        switch event.target {
        case .session(let id):
            NavigationLink(value: AnalyticsRoute.session(id)) {
                rowContent(event, hasTarget: true)
            }
            .buttonStyle(.plain)
        case .some(let target):
            Button { entrySheet = DiaryEntrySheet(editing: target) } label: {
                rowContent(event, hasTarget: true)
            }
            .buttonStyle(.plain)
        case nil:
            rowContent(event, hasTarget: false)
        }
    }

    private func rowContent(_ event: TimelineEvent, hasTarget: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            TimelineRow(event: event)
            if hasTarget {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.top, 5)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The nights behind a sleep average: one row each, newest first, opening
/// the same sleep form the diary uses.
struct SleepNightsView: View {
    @Bindable var store: AnalyticsStore
    @Environment(SleepStore.self) private var sleepStore
    @State private var entrySheet: DiaryEntrySheet?

    var body: some View {
        let nights = sleepStore.sessions(in: store.snapshot.interval)
            .filter { $0.kind == .night }
            .sorted { $0.start > $1.start }
        AnalyticsDetailScaffold(title: L("Ночи", "Nights"), store: store) {
            if nights.isEmpty {
                AnalyticsQuietNote(text: L("В этом периоде ночей нет.", "No nights in this period."))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(nights) { night in
                        Button { entrySheet = .sleep(editing: night.id) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DateFormatting.fullDate(night.day))
                                        .font(.lora(14, weight: .medium))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(DateFormatting.timeRange(from: night.start, to: night.end))
                                        .font(.lora(12).monospacedDigit())
                                        .foregroundStyle(AppTheme.inkSoft)
                                    if night.isSuperseded {
                                        Text(L("не входит в итог: перекрыта другой записью", "not counted: covered by another record"))
                                            .font(.lora(11))
                                            .foregroundStyle(AppTheme.inkSoft)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(DurationFormatting.compact(night.totalSleep))
                                    .font(.lora(14, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if night.id != nights.last?.id { Divider().overlay(AppTheme.border) }
                    }
                }
                .padding(16)
                .parchmentCard(padding: 0)
            }
        }
        .sheet(item: $entrySheet) { sheet in
            DiaryEntrySheetView(sheet: sheet, day: Date.now)
        }
    }
}
