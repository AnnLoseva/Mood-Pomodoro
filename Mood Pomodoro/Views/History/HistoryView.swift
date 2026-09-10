//
//  HistoryView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Query(sort: \FocusSession.startDate, order: .reverse) private var sessions: [FocusSession]

    private var finishedSessions: [FocusSession] {
        sessions.filter { !$0.isActive }
    }

    private var sections: [HistoryDaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: finishedSessions) { calendar.startOfDay(for: $0.startDate) }
        return grouped.keys.sorted(by: >).map { day in
            HistoryDaySection(
                day: day,
                title: DateFormatting.historySectionTitle(day),
                sessions: (grouped[day] ?? []).sorted { $0.startDate > $1.startDate }
            )
        }
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
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.title)
                                        .font(.lora(13, weight: .semibold))
                                        .foregroundStyle(AppTheme.inkSoft)
                                        .padding(.horizontal, 4)

                                    ForEach(section.sessions, id: \.id) { session in
                                        NavigationLink(value: session.id) {
                                            SessionRow(session: session)
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                sessionManager.delete(session)
                                            } label: {
                                                Label("Удалить", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
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

private struct HistoryDaySection: Identifiable {
    let day: Date
    let title: String
    let sessions: [FocusSession]
    var id: Date { day }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 14) {
            if let mood = session.sortedCheckIns.last?.mood {
                MoodImage(mood: mood, size: 44)
            } else {
                Text("🍄")
                    .font(.system(size: 28))
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.activity)
                    .font(.lora(17, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                Text(DateFormatting.fullDate(session.startDate))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                Text(DateFormatting.timeRange(from: session.startDate, to: session.endDate))
                    .font(.lora(13).monospacedDigit())
                    .foregroundStyle(AppTheme.inkSoft)
                Text(durationLine)
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

    private var durationLine: String {
        let total = DurationFormatting.compact(session.totalDuration())
        let count = session.checkIns?.count ?? 0
        let checkIns = "\(count) check-in"
        if session.breakDuration() > 0 {
            let active = DurationFormatting.compact(session.activeWorkDuration())
            let pause = DurationFormatting.compact(session.breakDuration())
            return "\(total) · \(active) активно · \(pause) перерыв · \(checkIns)"
        }
        return "\(total) · \(checkIns)"
    }
}
