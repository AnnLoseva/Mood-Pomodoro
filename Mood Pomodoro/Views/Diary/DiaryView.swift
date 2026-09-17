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
/// Shared by iPhone and iPad (like История and Аналитика); the month layout
/// spreads into two columns at regular width instead of getting its own view.
struct DiaryView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case day
        case month
        var id: String { rawValue }
        var title: String { self == .day ? L("День", "Day") : L("Месяц", "Month") }
    }

    @Environment(SessionManager.self) private var sessionManager
    @Environment(SleepStore.self) private var sleepStore
    @Environment(AppTabs.self) private var tabs
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.iPadSidebarHidden) private var iPadSidebarHidden
    @Query(sort: \CycleEntry.date, order: .reverse) private var cycleEntries: [CycleEntry]

    @State private var mode: Mode = .day
    @State private var selectedDate: Date = .now
    @State private var timelineSpan: TimelineSpan = .day
    @State private var showQuickCheckIn = false
    @State private var entrySheet: DiaryEntrySheet?
    @State private var showExport = false
    @State private var editingDay: Date?
    @State private var freezeDiaryScroll = false

    private let calendar = Calendar.current

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

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
                                addMenu
                                DiaryPeriodContent(
                                    selectedDate: selectedDate,
                                    isDayMode: mode == .day,
                                    isWide: isWide,
                                    isToday: isToday,
                                    timelineSpan: $timelineSpan,
                                    onQuickMood: { showQuickCheckIn = true },
                                    onAdd: { entrySheet = $0 },
                                    onEdit: { target, day in
                                        editingDay = day
                                        entrySheet = DiaryEntrySheet(editing: target)
                                    },
                                    onSelectDay: { day in
                                        selectedDate = day
                                        mode = .day
                                        timelineSpan = .day
                                    }
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
            .onChange(of: tabs.diaryDay) { _, day in
                guard let day else { return }
                selectedDate = day
                mode = .day
                timelineSpan = .day
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { item in
                let isSelected = item == mode
                Button {
                    mode = item
                    timelineSpan = item == .day ? .day : .month
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
            if !isToday {
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

    private var stepper: some View {
        DiaryPeriodStepper(
            title: mode == .day ? dayTitle : monthTitle,
            subtitle: mode == .day
                ? AnalyticsService.cycleDay(for: selectedDate, marks: cycleEntries.map(\.mark) + sleepStore.cycleMarks)
                    .map { L("🌸 День цикла: \($0)", "🌸 Cycle day: \($0)") }
                : nil,
            onPrevious: { shift(by: -1) },
            onNext: { shift(by: 1) },
            onTapTitle: mode == .day ? { mode = .month; timelineSpan = .month } : nil
        )
    }

    private var dayTitle: String {
        DateFormatting.historySectionTitle(selectedDate, calendar: calendar)
    }

    private var monthTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).year().locale(AppLanguage.current.locale)).localizedCapitalized
    }

    private func shift(by amount: Int) {
        let component: Calendar.Component = mode == .day ? .day : .month
        guard let shifted = calendar.date(byAdding: component, value: amount, to: selectedDate) else { return }
        selectedDate = shifted
    }
}
