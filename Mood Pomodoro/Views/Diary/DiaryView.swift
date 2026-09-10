//
//  DiaryView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// The Дневник tab: one day or one month, assembled from records the app
/// already has. Everything on screen is derived — the user is never asked to
/// re-enter an activity a session already knows about, or a mood already
/// answered in a check-in.
///
/// Shared by iPhone and iPad (like История and Аналитика); the month layout
/// spreads into two columns at regular width instead of getting its own view.
struct DiaryView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case day = "День"
        case month = "Месяц"
        var id: String { rawValue }
    }

    @Environment(SessionManager.self) private var sessionManager

    @Query private var sessions: [FocusSession]
    @Query private var checkIns: [CheckIn]
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]
    @Query(sort: \CycleEntry.date, order: .reverse) private var cycleEntries: [CycleEntry]

    @State private var mode: Mode = .day
    @State private var selectedDate: Date = .now
    @State private var showQuickCheckIn = false
    @State private var showCycleSheet = false

    private let calendar = Calendar.current

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    private var dailySummary: DailySummary {
        AnalyticsService.dailySummary(
            date: selectedDate,
            sessions: sessions,
            checkIns: checkIns,
            cycleEntries: cycleEntries,
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
                                switch mode {
                                case .day:
                                    DiaryDayView(
                                        summary: dailySummary,
                                        isToday: isToday,
                                        onAddMood: { showQuickCheckIn = true },
                                        onEditCycle: { showCycleSheet = true }
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
                    Text("Дневник")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                if !isToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сегодня") { selectedDate = .now }
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.forest)
                    }
                }
            }
            .sheet(isPresented: $showQuickCheckIn) {
                QuickCheckInSheet(sessionID: sessionManager.activeSession?.id)
            }
            .sheet(isPresented: $showCycleSheet) {
                CycleLogSheet(date: selectedDate)
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
                    Text(item.rawValue)
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

    private var stepper: some View {
        DiaryPeriodStepper(
            title: mode == .day ? dayTitle : monthTitle,
            subtitle: mode == .day ? dailySummary.cycleDay.map { "🌸 День цикла: \($0)" } : nil,
            onPrevious: { shift(by: -1) },
            onNext: { shift(by: 1) },
            onTapTitle: mode == .day ? { mode = .month } : nil
        )
    }

    private var dayTitle: String {
        DateFormatting.historySectionTitle(selectedDate, calendar: calendar)
    }

    private var monthTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).year()).localizedCapitalized
    }

    private func shift(by amount: Int) {
        let component: Calendar.Component = mode == .day ? .day : .month
        guard let shifted = calendar.date(byAdding: component, value: amount, to: selectedDate) else { return }
        selectedDate = shifted
    }
}
