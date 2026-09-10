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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 6) {
                    Text(session.activity)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(formattedElapsed(session.elapsedActiveTime(asOf: context.date)))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if session.isPaused {
                        Label("На паузе", systemImage: "pause.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !session.sortedCheckIns.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(session.sortedCheckIns.suffix(6), id: \.id) { checkIn in
                            Text(checkIn.mood.emoji)
                                .font(.title2)
                        }
                    }
                }

                Button {
                    showQuickCheckIn = true
                } label: {
                    Text("Как я сейчас?")
                        .font(.headline)
                        .frame(maxWidth: 420)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button {
                        session.isPaused ? sessionManager.resume() : sessionManager.pause()
                    } label: {
                        Label(session.isPaused ? "Продолжить" : "Пауза",
                              systemImage: session.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showFinishConfirm = true
                    } label: {
                        Label("Завершить", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal)

                Button("Отменить сессию", role: .destructive) {
                    showCancelConfirm = true
                }
                .font(.footnote)
                .padding(.top, 4)

                Spacer()
            }
        }
        .sheet(isPresented: $showQuickCheckIn) {
            QuickCheckInSheet(sessionID: session.id)
        }
        .confirmationDialog("Завершить сессию?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Завершить") { sessionManager.finish() }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Отменить сессию без сохранения?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Отменить сессию", role: .destructive) { sessionManager.cancel() }
            Button("Назад", role: .cancel) {}
        }
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
