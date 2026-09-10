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
            Group {
                if finishedSessions.isEmpty {
                    ContentUnavailableView(
                        "Пока нет истории",
                        systemImage: "clock",
                        description: Text("Заверши первую сессию, чтобы увидеть её здесь")
                    )
                } else {
                    List(finishedSessions, id: \.id) { session in
                        NavigationLink(value: session.id) {
                            SessionRow(session: session)
                        }
                    }
                }
            }
            .navigationTitle("История")
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
        VStack(alignment: .leading, spacing: 4) {
            Text(session.activity).font(.headline)
            HStack(spacing: 8) {
                Text(durationText)
                Text("·")
                Text("\(session.checkIns.count) check-ins")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
