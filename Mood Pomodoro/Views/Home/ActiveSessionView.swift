//
//  ActiveSessionView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct ActiveSessionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Query(sort: \FactorCategory.sortOrder) private var allCategories: [FactorCategory]
    let session: FocusSession

    @State private var showQuickCheckIn = false
    @State private var showFinishConfirm = false
    @State private var showCancelConfirm = false
    @State private var showConditionsPicker = false
    @State private var conditionsSelection: [FactorCategory: FactorOption] = [:]

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(session.activity)
                            .font(.lora(19, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        Text(formattedElapsed(session.elapsedActiveTime(asOf: context.date)))
                            .font(.lora(60, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .monospacedDigit()
                        if session.isPaused {
                            VStack(spacing: 4) {
                                Label("🌙 Перерыв", systemImage: "moon.fill")
                                    .font(.lora(15, weight: .medium))
                                    .foregroundStyle(AppTheme.rustDeep)
                                Text(formattedElapsed(session.breakDuration(asOf: context.date)))
                                    .font(.lora(22, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                                    .monospacedDigit()
                                Text("Ты можешь спокойно отдохнуть.")
                                    .font(.lora(13))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        } else {
                            Text("🟢 Работа")
                                .font(.lora(13, weight: .medium))
                                .foregroundStyle(AppTheme.forest)
                        }
                    }

                    if !session.sortedCheckIns.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(session.sortedCheckIns.suffix(6), id: \.id) { checkIn in
                                MoodImage(mood: checkIn.mood, size: 40)
                            }
                        }
                    }

                    ConditionsSummaryView(
                        title: "Условия",
                        chips: session.activeConditions(asOf: context.date).map(\.asChip),
                        actionTitle: "Изменить",
                        onTap: { openConditionsPicker() }
                    )

                    if !session.isPaused {
                        Button {
                            showQuickCheckIn = true
                        } label: {
                            Text("Как я сейчас?")
                        }
                        .buttonStyle(.goblinPrimary)
                    }

                    HStack(spacing: 14) {
                        Button {
                            session.isPaused ? sessionManager.resume() : sessionManager.pause()
                        } label: {
                            Label(session.isPaused ? "Продолжить" : "Пауза",
                                  systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(.goblinSecondary)

                        Button {
                            showFinishConfirm = true
                        } label: {
                            Label("Завершить", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.goblinSecondary)
                    }

                    Button("Отменить сессию", role: .destructive) {
                        showCancelConfirm = true
                    }
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.rustDeep)
                    .padding(.top, 2)
                }
                .parchmentCard(padding: 24)
                .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showQuickCheckIn) {
            QuickCheckInSheet(sessionID: session.id)
        }
        .sheet(isPresented: $showConditionsPicker) {
            ConditionsPickerSheet(selection: $conditionsSelection) {
                sessionManager.updateConditions(conditionsSelection, for: session)
            }
        }
        .goblinConfirmation(
            isPresented: $showFinishConfirm,
            title: "Завершить сессию?",
            confirmTitle: "Завершить",
            onConfirm: { sessionManager.finish() }
        )
        .goblinConfirmation(
            isPresented: $showCancelConfirm,
            title: "Отменить сессию?",
            message: "Сессия не будет сохранена",
            confirmTitle: "Отменить сессию",
            isDestructive: true,
            onConfirm: { sessionManager.cancel() }
        )
    }

    /// Seeds the picker's selection from the conditions active right now,
    /// resolving each snapshot entry back to its live `FactorCategory`/
    /// `FactorOption` (the snapshot only carries ids + names).
    private func openConditionsPicker() {
        let active = session.activeConditions(asOf: .now)
        var resolved: [FactorCategory: FactorOption] = [:]
        for entry in active {
            guard let category = allCategories.first(where: { $0.id == entry.categoryID }),
                  let option = (category.options ?? []).first(where: { $0.id == entry.optionID }) else { continue }
            resolved[category] = option
        }
        conditionsSelection = resolved
        showConditionsPicker = true
    }

    private func formattedElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
