//
//  QuickCheckInSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// Two-step manual check-in: pick a mood, then (optionally) a reason.
/// Presented both from the "Как я сейчас?" button and from tapping a
/// delivered notification's body.
struct QuickCheckInSheet: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID?
    /// When set (opened from a "Почему так?" notification tap), the sheet
    /// skips the mood step and fills in the reason on this existing check-in
    /// instead of creating a new one.
    let existingCheckInID: UUID?

    @State private var selectedMood: Mood?

    init(sessionID: UUID?, presetMood: Mood? = nil, existingCheckInID: UUID? = nil) {
        self.sessionID = sessionID
        self.existingCheckInID = existingCheckInID
        _selectedMood = State(initialValue: presetMood)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.parchmentCard.ignoresSafeArea()

                VStack(spacing: 24) {
                    if let mood = selectedMood {
                        ReasonPickerView(mood: mood) { reason in
                            save(mood: mood, reason: reason)
                        }
                    } else {
                        MoodPickerView { mood in
                            selectedMood = mood
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Как ты?")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .font(.lora(15))
                        .foregroundStyle(AppTheme.forest)
                }
                if selectedMood != nil && existingCheckInID == nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selectedMood = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .foregroundStyle(AppTheme.forest)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(mood: Mood, reason: String?) {
        if let existingCheckInID {
            sessionManager.updateReason(reason, for: existingCheckInID)
        } else {
            let session = sessionID.flatMap { sessionManager.session(withID: $0) } ?? sessionManager.activeSession
            sessionManager.addCheckIn(mood: mood, reason: reason, to: session)
        }
        dismiss()
    }
}

private struct MoodPickerView: View {
    let onSelect: (Mood) -> Void

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Mood.orderedCases) { mood in
                Button {
                    onSelect(mood)
                } label: {
                    HStack(spacing: 16) {
                        MoodImage(mood: mood, size: 48)
                        Text(mood.label)
                            .font(.lora(18, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.parchment.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1.25)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReasonPickerView: View {
    @Environment(ReasonsStore.self) private var reasonsStore
    let mood: Mood
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            MoodImage(mood: mood, size: 64)
            VStack(spacing: 10) {
                ForEach(reasonsStore.reasons(for: mood), id: \.self) { reason in
                    Button {
                        onSelect(reason)
                    } label: {
                        Text(reason)
                            .font(.lora(16))
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.parchment.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1.25)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Пропустить") {
                onSelect(nil)
            }
            .font(.lora(14))
            .foregroundStyle(AppTheme.inkSoft)
            .padding(.top, 4)
        }
    }
}
