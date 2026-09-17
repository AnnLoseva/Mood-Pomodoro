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
                        ReasonPickerView(mood: mood, showsLevels: existingCheckInID == nil) { answer in
                            save(mood: mood, answer: answer)
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
        .goblinChrome()
    }

    private func save(mood: Mood, answer: CheckInAnswer) {
        if let existingCheckInID {
            sessionManager.updateReason(answer.reason, for: existingCheckInID)
            dismiss()
            return
        }
        let session = sessionID.flatMap { sessionManager.session(withID: $0) } ?? sessionManager.activeSession
        // A running session takes the check-in so it keeps its conditions
        // snapshot and check-in scheduling; otherwise the mood is recorded on
        // its own — the same `CheckIn` type either way.
        if let session, session.state == .active {
            sessionManager.addCheckIn(
                mood: mood,
                energy: answer.energy,
                motivation: answer.motivation,
                reason: answer.reason,
                motivationReason: answer.motivationReason,
                note: answer.note,
                to: session
            )
        } else {
            sessionManager.addStandaloneCheckIn(
                mood: mood,
                energy: answer.energy,
                motivation: answer.motivation,
                reason: answer.reason,
                motivationReason: answer.motivationReason,
                note: answer.note
            )
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
                            .fill(AppTheme.chipFill)
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

/// Everything the second step can collect. Only the mood, picked in the
/// first step, is required — every field here may stay nil.
private struct CheckInAnswer {
    var reason: String?
    var note: String?
    var energy: EnergyLevel?
    var motivation: StudyMotivation?
    var motivationReason: String?
}

private struct ReasonPickerView: View {
    @Environment(ReasonsStore.self) private var reasonsStore
    let mood: Mood
    /// Off when the sheet was opened to fill in the reason on a check-in
    /// that already exists — that flow only edits the reason.
    let showsLevels: Bool
    let onSelect: (CheckInAnswer) -> Void

    @State private var note: String = ""
    @State private var energy: EnergyLevel?
    @State private var motivation: StudyMotivation?
    @State private var motivationReason: String?

    private var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A different level means a different list; an answer from the
    /// previous one would be attached to a question no longer on screen.
    private var motivationBinding: Binding<StudyMotivation?> {
        Binding(
            get: { motivation },
            set: { newValue in
                if newValue != motivation { motivationReason = nil }
                motivation = newValue
            }
        )
    }

    private func answer(reason: String?) -> CheckInAnswer {
        CheckInAnswer(
            reason: reason,
            note: trimmedNote,
            energy: energy,
            motivation: motivation,
            motivationReason: motivationReason
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MoodImage(mood: mood, size: 64)
                VStack(spacing: 10) {
                    ForEach(reasonsStore.reasons(for: mood), id: \.self) { reason in
                        Button {
                            onSelect(answer(reason: reason))
                        } label: {
                            Text(Ldata(reason))
                                .font(.lora(16))
                                .foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppTheme.chipFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1.25)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if showsLevels {
                    VStack(alignment: .leading, spacing: 14) {
                        levelSection(L("🔋 Сколько сил", "🔋 Energy left")) {
                            LevelPickerRow(selection: $energy, size: 36)
                        }
                        levelSection(L("🔥 Мотивация к текущему занятию", "🔥 Motivation for what I'm doing")) {
                            LevelPickerRow(selection: motivationBinding, size: 36)
                            if let motivation {
                                FlowLayout(spacing: 8) {
                                    ForEach(reasonsStore.reasons(for: motivation), id: \.self) { item in
                                        DiaryChip(title: Ldata(item), isSelected: motivationReason == item) {
                                            motivationReason = motivationReason == item ? nil : item
                                        }
                                    }
                                }
                            }
                        }
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
                            .fill(AppTheme.chipFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1.25)
                    )

                Button(L("Пропустить", "Skip")) {
                    onSelect(answer(reason: nil))
                }
                .font(.lora(14))
                .foregroundStyle(AppTheme.inkSoft)
                .padding(.top, 4)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func levelSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
