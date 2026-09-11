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

    @Query private var sessions: [FocusSession]
    @Query private var checkIns: [CheckIn]
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]
    @Query(sort: \CycleEntry.date, order: .reverse) private var cycleEntries: [CycleEntry]
    @Query private var supportEntries: [SupportEntry]
    @Query private var notes: [JournalNote]
    @Query private var conditionEvents: [ConditionEvent]

    @State private var mode: Mode = .day
    @State private var selectedDate: Date = .now
    @State private var showQuickCheckIn = false
    @State private var entrySheet: DiaryEntrySheet?
    @State private var showExport = false

    private let calendar = Calendar.current

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    private var dailySummary: DailySummary {
        AnalyticsService.dailySummary(
            date: selectedDate,
            sessions: sessions,
            checkIns: checkIns,
            cycleEntries: cycleEntries,
            supportEntries: supportEntries,
            notes: notes,
            diaryFactors: conditionEvents,
            calendar: calendar
        )
    }

    private var monthlySummary: MonthlySummary {
        AnalyticsService.monthlySummary(
            month: selectedDate,
            sessions: sessions,
            checkIns: checkIns,
            categories: categories,
            cycleEntries: cycleEntries,
            supportEntries: supportEntries,
            calendar: calendar
        )
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
                                addMenu
                                switch mode {
                                case .day:
                                    DiaryDayView(
                                        summary: dailySummary,
                                        isToday: isToday,
                                        onQuickMood: { showQuickCheckIn = true },
                                        onAdd: { entrySheet = $0 },
                                        onEdit: { entrySheet = DiaryEntrySheet(editing: $0) }
                                    )
                                case .month:
                                    DiaryMonthView(summary: monthlySummary, isWide: isWide) { day in
                                        selectedDate = day
                                        mode = .day
                                    }
                                }
                            }
                            .frame(maxWidth: isWide ? 1100 : nil)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("Дневник", "Diary"))
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .topBarLeading) {
                    LanguageMenu()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isToday {
                        Button(L("Сегодня", "Today")) { selectedDate = .now }
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.forest)
                    }
                    Button {
                        showExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(AppTheme.forest)
                    .accessibilityLabel(L("Экспорт", "Export"))
                }
            }
            .sheet(isPresented: $showQuickCheckIn) {
                QuickCheckInSheet(sessionID: sessionManager.activeSession?.id)
            }
            .sheet(item: $entrySheet) { sheet in
                DiaryEntrySheetView(sheet: sheet, day: selectedDate)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { item in
                let isSelected = item == mode
                Button {
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.lora(13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(isSelected ? AppTheme.forest : AppTheme.parchment.opacity(0.5)))
                        .overlay(Capsule().stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// Visible but quiet: one capsule under the date. Every form it opens
    /// starts on the day being viewed and lets the date be changed.
    private var addMenu: some View {
        Menu {
            Button(L("🌿 Деятельность", "🌿 Activity")) { entrySheet = .activity(editing: nil) }
            Button(L("🙂 Настроение", "🙂 Mood")) { entrySheet = .mood(editing: nil) }
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
            subtitle: mode == .day ? dailySummary.cycleDay.map { L("🌸 День цикла: \($0)", "🌸 Cycle day: \($0)") } : nil,
            onPrevious: { shift(by: -1) },
            onNext: { shift(by: 1) },
            onTapTitle: mode == .day ? { mode = .month } : nil
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
