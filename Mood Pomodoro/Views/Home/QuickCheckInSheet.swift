//
//  QuickCheckInSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// Two-step manual check-in: pick a mood, then (optionally) a reason and a
/// note. Presented from the "Как я сейчас?" buttons (in a session, from the
/// idle screen, or from the diary) and from tapping a delivered
/// notification's body. When no session is running the check-in is saved
/// standalone — logging a mood never requires starting one.
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
                        ReasonPickerView(mood: mood) { reason, note in
                            save(mood: mood, reason: reason, note: note)
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
                    Text(L("Как ты?", "How are you?"))
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Закрыть", "Close")) { dismiss() }
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

    private func save(mood: Mood, reason: String?, note: String?) {
        if let existingCheckInID {
            sessionManager.updateReason(reason, for: existingCheckInID)
            dismiss()
            return
        }
        let session = sessionID.flatMap { sessionManager.session(withID: $0) } ?? sessionManager.activeSession
        // A running session takes the check-in so it keeps its conditions
        // snapshot and check-in scheduling; otherwise the mood is recorded on
        // its own — the same `CheckIn` type either way.
        if let session, session.state == .active {
            sessionManager.addCheckIn(mood: mood, reason: reason, note: note, to: session)
        } else {
            sessionManager.addStandaloneCheckIn(mood: mood, reason: reason, note: note)
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
    let onSelect: (String?, String?) -> Void

    @State private var note: String = ""

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MoodImage(mood: mood, size: 64)
                VStack(spacing: 10) {
                    ForEach(reasonsStore.reasons(for: mood), id: \.self) { reason in
                        Button {
                            onSelect(reason, trimmedNote)
                        } label: {
                            Text(Ldata(reason))
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

                // Optional — a place for the sentence a stock reason doesn't
                // cover. Never required to save a check-in.
                TextField(L("Заметка (необязательно)", "Note (optional)"), text: $note)
                    .font(.lora(14))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.parchment.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1.25)
                    )

                Button(L("Пропустить", "Skip")) {
                    onSelect(nil, trimmedNote)
                }
                .font(.lora(14))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.top, 4)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
