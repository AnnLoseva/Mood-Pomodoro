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

    @State private var selectedMood: Mood?

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Как ты?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                if selectedMood != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selectedMood = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(mood: Mood, reason: String?) {
        let session = sessionID.flatMap { sessionManager.session(withID: $0) } ?? sessionManager.activeSession
        sessionManager.addCheckIn(mood: mood, reason: reason, to: session)
        dismiss()
    }
}

private struct MoodPickerView: View {
    let onSelect: (Mood) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Mood.orderedCases) { mood in
                Button {
                    onSelect(mood)
                } label: {
                    HStack(spacing: 16) {
                        Text(mood.emoji).font(.system(size: 36))
                        Text(mood.label).font(.title3)
                        Spacer()
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
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
            Text(mood.emoji).font(.system(size: 48))
            VStack(spacing: 10) {
                ForEach(reasonsStore.reasons(for: mood), id: \.self) { reason in
                    Button {
                        onSelect(reason)
                    } label: {
                        Text(reason)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Пропустить") {
                onSelect(nil)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }
}
