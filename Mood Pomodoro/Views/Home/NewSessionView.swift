//
//  NewSessionView.swift
//  Mood Pomodoro
//

import SwiftUI

struct NewSessionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var activity: String = ""
    @State private var intervalMinutes: Int = 10

    private let intervalOptions = [5, 10, 15, 20, 30]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("🍅")
                    .font(.system(size: 64))
                Text("Новая сессия")
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Чем занимаешься?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Например, Математика", text: $activity)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Как часто спрашивать?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Интервал", selection: $intervalMinutes) {
                        ForEach(intervalOptions, id: \.self) { minutes in
                            Text("\(minutes) мин").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal)

            Button {
                sessionManager.startSession(activity: trimmedActivity, intervalMinutes: intervalMinutes)
            } label: {
                Text("Начать")
                    .font(.headline)
                    .frame(maxWidth: 420)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedActivity.isEmpty)
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
    }

    private var trimmedActivity: String {
        activity.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
