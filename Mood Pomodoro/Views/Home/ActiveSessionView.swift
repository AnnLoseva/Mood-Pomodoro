//
//  ActiveSessionView.swift
//  Mood Pomodoro
//

import SwiftUI

struct ActiveSessionView: View {
    @Environment(SessionManager.self) private var sessionManager
    let session: FocusSession

    @State private var showQuickCheckIn = false
    @State private var showFinishConfirm = false
    @State private var showCancelConfirm = false

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
                            Label("На паузе", systemImage: "pause.fill")
                                .font(.lora(13, weight: .medium))
                                .foregroundStyle(AppTheme.rustDeep)
                        }
                    }

                    if !session.sortedCheckIns.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(session.sortedCheckIns.suffix(6), id: \.id) { checkIn in
                                MoodImage(mood: checkIn.mood, size: 40)
                            }
                        }
                    }

                    Button {
                        showQuickCheckIn = true
                    } label: {
                        Text("Как я сейчас?")
                    }
                    .buttonStyle(.goblinPrimary)

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
