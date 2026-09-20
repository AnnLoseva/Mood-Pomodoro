//
//  TodoSessionPromptSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// What is offered after a session ends — a small card at the bottom, not a window that has to be
/// answered. The session is already saved before it appears; ignoring it (or the ✕) changes
/// nothing, and it goes away by itself. A session that ended is not a task that finished, so
/// nothing here is ever sent unless the button is pressed.
struct TodoSessionCard: View {
    @Environment(TodoIntegrationCoordinator.self) private var integration
    let prompt: TodoSessionPrompt

    /// How long an unanswered card stays before it quietly leaves.
    static let idleLifetime: Duration = .seconds(20)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Занятие сохранено", "Session saved"))
                        .font(.lora(15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    integration.dismissPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Закрыть", "Close"))
            }

            switch prompt.progress {
            case .none:
                Button(actionTitle) { Task { await perform() } }
                    .buttonStyle(.goblinSecondary)
            case .queued:
                status(L("Сохранено. Отправится, как только ToDo List будет доступен.", "Saved. It will be sent as soon as ToDo List is available."))
            case .delivered:
                status(L("Отправлено в ToDo List.", "Sent to ToDo List."))
            case .handedOff:
                status(L("Передано в ToDo List.", "Handed to ToDo List."))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.parchmentCard)
                .shadow(color: AppTheme.ink.opacity(0.18), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.ink.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .task(id: prompt.id) {
            // Nobody has to answer: an untouched card leaves on its own.
            try? await Task.sleep(for: Self.idleLifetime)
            if integration.prompt?.id == prompt.id, integration.prompt?.progress == .none {
                integration.dismissPrompt()
            }
        }
    }

    private var subtitle: String? {
        switch prompt.kind {
        case .linkedTask(_, let title): L("Задача: \(title)", "Task: \(title)")
        case .standalone(let activity): Ldata(activity)
        }
    }

    private var actionTitle: String {
        switch prompt.kind {
        case .linkedTask: L("Отметить задачу выполненной", "Mark the task done")
        case .standalone: L("Добавить в сделанное", "Add to done")
        }
    }

    private func perform() async {
        switch prompt.kind {
        case .linkedTask: await integration.requestCompletion()
        case .standalone: await integration.requestCreateDone()
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.lora(13))
            .foregroundStyle(AppTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
