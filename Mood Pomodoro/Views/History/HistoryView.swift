//
//  HistoryView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \FocusSession.startDate, order: .reverse) private var sessions: [FocusSession]

    private var finishedSessions: [FocusSession] {
        sessions.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()

                if finishedSessions.isEmpty {
                    VStack(spacing: 10) {
                        MoodImage(mood: .neutral, size: 72)
                        Text("Пока нет истории")
                            .font(.lora(19, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Заверши первую сессию, чтобы увидеть её здесь")
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .parchmentCard()
                    .padding(.horizontal, 32)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(finishedSessions, id: \.id) { session in
                                NavigationLink(value: session.id) {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("История")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let session = sessions.first(where: { $0.id == id }) {
                    SessionDetailView(session: session)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 14) {
            if let mood = session.sortedCheckIns.last?.mood {
                MoodImage(mood: mood, size: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.activity)
                    .font(.lora(17, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                Text("\(durationText) · \(session.checkIns.count) check-in")
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.parchmentCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1.25)
        )
    }

    private var durationText: String {
        let end = session.endDate ?? .now
        let total = Int(end.timeIntervalSince(session.startDate))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
