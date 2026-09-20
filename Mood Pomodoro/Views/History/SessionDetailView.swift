//
//  SessionDetailView.swift
//  Mood Pomodoro
//

import SwiftUI
import Charts

struct SessionDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    let session: FocusSession

    @State private var showDeleteConfirm = false
    @State private var showEditor = false

    private var trajectory: [(minutes: Double, mood: Mood)] { AnalyticsService.sessionTrajectory(session) }

    var body: some View {
        ZStack {
            ForestBackdrop()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    durationCard

                    if trajectory.count >= 2 {
                        trajectoryCard
                    }

                    timelineCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .goblinChrome()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(Ldata(session.activity))
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    // Only a backdated session has times to correct.
                    if session.isManualEntry {
                        Button { showEditor = true } label: {
                            Image(systemName: "pencil")
                        }
                        .foregroundStyle(AppTheme.forest)
                        .accessibilityLabel(L("Изменить время и название", "Edit times and name"))
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundStyle(AppTheme.rustDeep)
                    .accessibilityLabel(L("Удалить сессию", "Delete session"))
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            DiaryEntrySheetView(sheet: .activity(editing: session.id), day: session.startDate)
        }
        .goblinConfirmation(
            isPresented: $showDeleteConfirm,
            title: L("Удалить сессию?", "Delete the session?"),
            message: L("Она исчезнет из дневника и больше не попадёт в аналитику.", "It will disappear from the diary and won't count in analytics anymore."),
            confirmTitle: L("Удалить", "Delete"),
            isDestructive: true,
            onConfirm: {
                sessionManager.delete(session)
                dismiss()
            }
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SessionTypePicker(selection: Binding(
                get: { session.sessionType },
                set: { sessionManager.setSessionType($0, for: session) }
            ), showsHint: false)
            if let title = session.sourceTaskTitle {
                Text(L("Задача из ToDo List: \(title)", "Task from ToDo List: \(title)"))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.forest)
            }
            Text(DateFormatting.fullDate(session.startDate))
                .font(.lora(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(DateFormatting.timeRange(from: session.startDate, to: session.endDate))
                .font(.lora(14).monospacedDigit())
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .parchmentCard()
    }

    private var timelineCard: some View {
        let events = session.timelineEvents
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index > 0, !DateFormatting.isSameDay(events[index - 1].timestamp, event.timestamp) {
                    Text(DateFormatting.fullDate(event.timestamp))
                        .font(.lora(12, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding(.top, 6)
                }
                TimelineRow(event: event)
            }
        }
        .padding(20)
        .parchmentCard()
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            durationRow(icon: "⏱", title: L("Всего", "Total"), value: DurationFormatting.compact(session.totalDuration()))
            durationRow(icon: "🌿", title: L("Активно", "Active"), value: DurationFormatting.compact(session.activeWorkDuration()))
            durationRow(icon: "☕", title: L("Перерыв", "Break"), value: DurationFormatting.compact(session.breakDuration()))
            durationRow(icon: "💬", title: "Check-ins", value: "\(session.checkIns?.count ?? 0)")
        }
        .padding(18)
        .parchmentCard()
    }

    private func durationRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Text("\(icon)  \(title)")
                .font(.lora(14))
                .foregroundStyle(AppTheme.inkSoft)
            Spacer()
            Text(value)
                .font(.lora(14, weight: .medium))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private var trajectoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Состояние во время сессии", "Mood during the session"))
                .font(.lora(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            Chart(Array(trajectory.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Минуты", point.minutes),
                    y: .value("Состояние", point.mood.scale)
                )
                .foregroundStyle(AppTheme.forest)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Минуты", point.minutes),
                    y: .value("Состояние", point.mood.scale)
                )
                .foregroundStyle(AppTheme.rust)
            }
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    if let raw = value.as(Int.self), let mood = Mood.orderedCases.first(where: { Int($0.scale) == raw }) {
                        AxisValueLabel { Text(mood.emoji) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    if let minutes = value.as(Int.self) {
                        AxisValueLabel(L("\(minutes)м", "\(minutes)m")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(18)
        .parchmentCard()
    }
}

/// The session's details as a sheet, for the places that have no navigation
/// stack of their own to push onto — the diary's chart and day list. It is
/// the same `SessionDetailView`, so type editing and delete-with-confirmation
/// behave identically wherever it is opened from.
struct SessionDetailSheet: View {
    let sessionID: UUID
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let session = sessionManager.session(withID: sessionID) {
                    SessionDetailView(session: session)
                } else {
                    ZStack {
                        ForestBackdrop()
                        Text(L("Эта сессия уже удалена.", "This session has been deleted."))
                            .font(.lora(15))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Закрыть", "Close")) { dismiss() }
                        .foregroundStyle(AppTheme.forest)
                }
            }
        }
        .goblinChrome()
    }
}
