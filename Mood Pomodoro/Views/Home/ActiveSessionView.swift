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
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(Ldata(session.activity))
                        .font(.lora(19, weight: .medium))
                        .foregroundStyle(AppTheme.inkSoft)
                    SessionClock(session: session)
                    if session.isPaused {
                        VStack(spacing: 4) {
                            Label(L("🌙 Перерыв", "🌙 Break"), systemImage: "moon.fill")
                                .font(.lora(15, weight: .medium))
                                .foregroundStyle(AppTheme.rustDeep)
                            BreakClock(session: session)
                            Text(L("Ты можешь спокойно отдохнуть.", "Take your time and rest."))
                                .font(.lora(13))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    } else {
                        Text(L("🟢 Работа", "🟢 Working"))
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
                    title: L("Условия", "Conditions"),
                    chips: session.activeConditions(asOf: .now).map(\.asChip),
                    actionTitle: L("Изменить", "Change"),
                    onTap: { openConditionsPicker() }
                )

                if !session.isPaused {
                    Button {
                        showQuickCheckIn = true
                    } label: {
                        Text(L("Как я сейчас?", "How am I feeling?"))
                    }
                    .buttonStyle(.goblinPrimary)
                }

                HStack(spacing: 14) {
                    Button {
                        session.isPaused ? sessionManager.resume() : sessionManager.pause()
                    } label: {
                        Label(session.isPaused ? L("Продолжить", "Resume") : L("Пауза", "Pause"),
                              systemImage: session.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.goblinSecondary)

                    Button {
                        showFinishConfirm = true
                    } label: {
                        Label(L("Завершить", "Finish"), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.goblinSecondary)
                }

                Button(L("Отменить сессию", "Cancel session"), role: .destructive) {
                    showCancelConfirm = true
                }
                .font(.lora(13))
                .foregroundStyle(AppTheme.rustDeep)
                .padding(.top, 2)
            }
            .parchmentCard(padding: 24)
            .padding(.horizontal, 24)
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
            title: L("Завершить сессию?", "Finish the session?"),
            confirmTitle: L("Завершить", "Finish"),
            onConfirm: { sessionManager.finish() }
        )
        .goblinConfirmation(
            isPresented: $showCancelConfirm,
            title: L("Отменить сессию?", "Cancel the session?"),
            message: L("Сессия не будет сохранена", "The session won't be saved"),
            confirmTitle: L("Отменить сессию", "Cancel session"),
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

}

private struct SessionClock: View {
    let session: FocusSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.formatted(session.elapsedActiveTime(asOf: context.date)))
                .font(.lora(60, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
        }
    }

    static func formatted(_ interval: TimeInterval) -> String {
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

private struct BreakClock: View {
    let session: FocusSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(SessionClock.formatted(session.breakDuration(asOf: context.date)))
                .font(.lora(22, weight: .medium))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
        }
    }
}
