//
//  TodoSessionPromptSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// What is offered after a session ends, and only that. The session is
/// already saved before this appears, and closing it changes nothing about
/// it: a session that ended is not a task that finished.
struct TodoSessionPromptSheet: View {
    @Environment(TodoIntegrationCoordinator.self) private var integration
    @Environment(\.dismiss) private var dismiss
    let prompt: TodoSessionPrompt

    var body: some View {
        VStack(spacing: 18) {
            Text(L("Занятие сохранено", "Session saved"))
                .font(.lora(20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            switch prompt.kind {
            case .linkedTask(_, let title):
                linked(title: title)
            case .standalone(let activity):
                standalone(activity: activity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(300), .medium])
        .presentationBackground(AppTheme.parchment)
    }

    private func linked(title: String) -> some View {
        VStack(spacing: 14) {
            Text(L("Задача: \(title)", "Task: \(title)"))
                .font(.lora(15))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
            switch prompt.progress {
            case .none:
                HStack(spacing: 12) {
                    Button(L("Продолжу позже", "I'll continue later")) { close() }
                        .buttonStyle(.goblinSecondary)
                    Button(L("Готово", "Done")) {
                        Task { await integration.requestCompletion() }
                    }
                    .buttonStyle(.goblinPrimary)
                }
            case .handedOff:
                status(L("Запрос передан в ToDo List — задача отметится там.", "The request was handed to ToDo List — the task will be marked there."))
                Button(L("Закрыть", "Close")) { close() }.buttonStyle(.goblinSecondary)
            case .queued:
                status(L("Запрос сохранён. Он уйдёт, как только ToDo List будет доступен.", "The request is saved. It will go as soon as ToDo List is available."))
                HStack(spacing: 12) {
                    Button(L("Закрыть", "Close")) { close() }.buttonStyle(.goblinSecondary)
                    Button(L("Отправить снова", "Try again")) {
                        Task { await integration.requestCompletion() }
                    }
                    .buttonStyle(.goblinPrimary)
                }
            }
        }
    }

    private func standalone(activity: String) -> some View {
        VStack(spacing: 14) {
            Text(Ldata(activity))
                .font(.lora(15))
                .foregroundStyle(AppTheme.inkSoft)
            switch prompt.progress {
            case .none:
                Text(L("Добавить в сделанное?", "Add to done?"))
                    .font(.lora(16, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                HStack(spacing: 12) {
                    Button(L("Не сейчас", "Not now")) { close() }
                        .buttonStyle(.goblinSecondary)
                    Button(L("Добавить", "Add")) {
                        Task { await integration.requestCreateDone() }
                    }
                    .buttonStyle(.goblinPrimary)
                }
            case .handedOff:
                status(L("Запрос передан в ToDo List.", "The request was handed to ToDo List."))
                Button(L("Закрыть", "Close")) { close() }.buttonStyle(.goblinSecondary)
            case .queued:
                status(L("Запрос сохранён. Он уйдёт, как только ToDo List будет доступен.", "The request is saved. It will go as soon as ToDo List is available."))
                Button(L("Закрыть", "Close")) { close() }.buttonStyle(.goblinSecondary)
            }
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.lora(14))
            .foregroundStyle(AppTheme.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func close() {
        integration.dismissPrompt()
        dismiss()
    }
}
