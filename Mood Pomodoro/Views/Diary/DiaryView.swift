//
//  DiaryView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// The Дневник tab: one day or one month. Most of it is derived from records
/// the app already has; "+ Добавить" covers the rest — including anything
/// the user remembers later, which lands on the day it actually happened.
///
/// Everything is read through `@Query`, so an entry added or edited here
/// (or synced from the other device) re-derives the day, the month and the
/// calendar colors on its own.
///
/// Shared by iPhone and iPad (like Аналитика); the month layout
/// spreads into two columns at regular width instead of getting its own view.
struct DiaryView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case day
        case month
        case all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: return L("День", "Day")
            case .month: return L("Месяц", "Month")
            case .all: return L("Общее", "Overall")
            }
        }
        var span: TimelineSpan {
            switch self {
            case .day: return .day
            case .month: return .month
            case .all: return .all
            }
        }
    }

    @Environment(SessionManager.self) private var sessionManager
    @Environment(SleepStore.self) private var sleepStore
    @Environment(AppTabs.self) private var tabs
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.iPadSidebarHidden) private var iPadSidebarHidden
    @Query(sort: \CycleEntry.date, order: .reverse) private var cycleEntries: [CycleEntry]

    @State private var selectedDate: Date = .now
    @State private var timelineSpan: TimelineSpan = .day
    /// The day tapped on the week/month chart, so "День" can open it.
    @State private var tappedDay: Date?
    @State private var showQuickCheckIn = false
    @State private var entrySheet: DiaryEntrySheet?
    @State private var showExport = false
    @State private var editingDay: Date?
    @State private var freezeDiaryScroll = false
    @State private var sessionSheet: SessionSheetID?
    @State private var showSearch = false
    /// Where a search result should go once the search sheet has closed.
    @State private var pendingSearchRoute: AnalyticsRoute?

    private struct SessionSheetID: Identifiable { let id: UUID }

    private let calendar = Calendar.current

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    /// The tab is whatever the chart's span says, so the chart's own
    /// Day / Week / Month / All picker and the tabs above can never disagree.
    private var mode: Mode {
        switch timelineSpan {
        case .day: return .day
        case .week, .month: return .month
        case .all: return .all
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()

                // Two-up month layout is chosen from the pane's real width,
                // not the size class: on iPad the sidebar can leave a detail
                // pane no wider than a phone's, where side-by-side cards
                // squeeze their labels apart.
                GeometryReader { proxy in
                    let isWide = proxy.size.width >= 700

                    VStack(spacing: 0) {
                        modePicker
                        ScrollView {
                            VStack(spacing: 16) {
                                stepper
                                HStack(spacing: 10) {
                                    addMenu
                                    searchButton
                                }
                                DiaryPeriodContent(
                                    selectedDate: selectedDate,
                                    isDayMode: mode == .day,
                                    isWide: isWide,
                                    isToday: isToday,
                                    timelineSpan: $timelineSpan,
                                    tappedDay: $tappedDay,
                                    onQuickMood: { showQuickCheckIn = true },
                                    onAdd: { entrySheet = $0 },
                                    onEdit: { target, day in
                                        // A session opens its own details (the same
                                        // screen everywhere); everything else its form.
                                        if case .session(let id) = target {
                                            sessionSheet = SessionSheetID(id: id)
                                            return
                                        }
                                        editingDay = day
                                        entrySheet = DiaryEntrySheet(editing: target)
                                    },
                                    onSelectDay: { day in
                                        tappedDay = nil
                                        selectedDate = day
                                        timelineSpan = .day
                                    },
                                    onStep: { shift(by: $0) }
                                )
                                .id("\(timelineSpan.rawValue)-\(calendar.startOfDay(for: selectedDate).timeIntervalSince1970)")
                            }
                            .frame(maxWidth: isWide ? 1100 : nil)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, isWide ? 20 : 12)
                            .padding(.vertical, 20)
                        }
                        .scrollDisabled(freezeDiaryScroll)
                        .onPreferenceChange(TimelineBlocksScrollKey.self) { freezeDiaryScroll = $0 }
                    }
                }
            }
            .hideRootNavigationBar()
            .goblinChrome()
            .sheet(isPresented: $showQuickCheckIn) {
                QuickCheckInSheet(sessionID: sessionManager.activeSession?.id)
            }
            .sheet(item: $entrySheet, onDismiss: { editingDay = nil }) { sheet in
                DiaryEntrySheetView(sheet: sheet, day: editingDay ?? selectedDate)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
            .sheet(item: $sessionSheet) { item in
                SessionDetailSheet(sessionID: item.id)
            }
            .sheet(isPresented: $showSearch, onDismiss: openPendingSearchRoute) {
                NavigationStack {
                    AnalyticsSearchView(store: nil, onOpen: { route in
                        pendingSearchRoute = route
                        showSearch = false
                    })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("Закрыть", "Close")) { showSearch = false }.foregroundStyle(AppTheme.forest)
                        }
                    }
                }
                .goblinChrome()
            }
            // A view rebuilt for another day or span starts with no tap.
            .onChange(of: selectedDate) { _, _ in tappedDay = nil }
            .onChange(of: timelineSpan) { _, _ in tappedDay = nil }
            .onChange(of: tabs.diaryDay) { _, day in
                guard let day else { return }
                selectedDate = day
                timelineSpan = .day
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { item in
                let isSelected = item == mode
                Button {
                    if item == .day, let tappedDay { selectedDate = tappedDay }
                    tappedDay = nil
                    timelineSpan = item.span
                } label: {
                    Text(item.title)
                        .font(.lora(13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(isSelected ? AppTheme.forest : AppTheme.chipFill))
                        .overlay(Capsule().stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if !isToday, mode != .all {
                Button(L("Сегодня", "Today")) { selectedDate = .now }
                    .font(.lora(13, weight: .medium))
                    .foregroundStyle(AppTheme.forest)
            }
            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.forest)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Экспорт", "Export"))
            if sizeClass != .regular {
                LanguageMenu()
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.leading, iPadSidebarHidden ? 56 : 16)
        .padding(.trailing, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    /// Visible but quiet: one capsule under the date. Every form it opens
    /// starts on the day being viewed and lets the date be changed.
    private var addMenu: some View {
        Menu {
            Button(L("✨ Эмоции", "✨ Emotions")) { entrySheet = .emotion(editing: nil) }
            Button(L("⚡ Импульс", "⚡ Impulse")) { entrySheet = .impulse(editing: nil) }
            Button(L("🙂 Настроение", "🙂 Mood")) { entrySheet = .mood(editing: nil) }
            Button(L("🍽 Еда", "🍽 Food")) { entrySheet = .food(editing: nil) }
            Button(L("🍎 Голод / аппетит", "🍎 Hunger / appetite")) { entrySheet = .hunger(editing: nil) }
            Button(L("🌙 Сон", "🌙 Sleep")) { entrySheet = .sleep(editing: nil) }
            Button(L("🌿 Деятельность", "🌿 Activity")) { entrySheet = .activity(editing: nil) }
            Button(L("💊 Поддержка", "💊 Support")) { entrySheet = .support }
            Button(L("🌸 Цикл", "🌸 Cycle")) { entrySheet = .cycle }
            Button(L("☕ Фактор", "☕ Factor")) { entrySheet = .factor(editing: nil) }
            Button(L("📝 Заметку", "📝 Note")) { entrySheet = .note(editing: nil) }
        } label: {
            Label(L("Добавить", "Add"), systemImage: "plus")
                .font(.lora(14, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppTheme.parchmentCard))
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1.25))
        }
        .accessibilityLabel(L("Добавить запись", "Add entry"))
    }

    /// Search sits beside "Добавить": finding a record and adding one are the
    /// two things done to the diary itself.
    private var searchButton: some View {
        Button { showSearch = true } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .frame(width: 44, height: 40)
                .background(Capsule().fill(AppTheme.parchmentCard))
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1.25))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Поиск по дневнику и данным", "Search the diary and data"))
    }

    private var stepper: some View {
        DiaryPeriodStepper(
            title: stepperTitle,
            subtitle: mode == .day
                ? AnalyticsService.cycleDay(for: selectedDate, marks: cycleEntries.map(\.mark) + sleepStore.cycleMarks)
                    .map { L("🌸 День цикла: \($0)", "🌸 Cycle day: \($0)") }
                : nil,
            onPrevious: { shift(by: -1) },
            onNext: { shift(by: 1) },
            onTapTitle: mode == .day ? { timelineSpan = .month } : nil,
            showsArrows: timelineSpan != .all
        )
    }

    private var stepperTitle: String {
        switch timelineSpan {
        case .day: return dayTitle
        case .week: return weekTitle
        case .month: return monthTitle
        case .all: return L("Всё время", "All time")
        }
    }

    private var weekTitle: String {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return dayTitle }
        let last = interval.end.addingTimeInterval(-1)
        let year = last.formatted(.dateTime.year().locale(AppLanguage.current.locale))
        return DateFormatting.compactDate(interval.start) + " – " + DateFormatting.compactDate(last) + " " + year
    }

    private var dayTitle: String {
        DateFormatting.historySectionTitle(selectedDate, calendar: calendar)
    }

    private var monthTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).year().locale(AppLanguage.current.locale)).localizedCapitalized
    }

    private func openPendingSearchRoute() {
        guard let route = pendingSearchRoute else { return }
        pendingSearchRoute = nil
        switch route {
        case .day(let day):
            selectedDate = day
            timelineSpan = .day
        case .session(let id):
            sessionSheet = SessionSheetID(id: id)
        default:
            tabs.openAnalytics(route)
        }
    }

    private func shift(by amount: Int) {
        guard let component = timelineSpan.calendarComponent,
              let shifted = calendar.date(byAdding: component, value: amount, to: selectedDate) else { return }
        selectedDate = shifted
    }
}
