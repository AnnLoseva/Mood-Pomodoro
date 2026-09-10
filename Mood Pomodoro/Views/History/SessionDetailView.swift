//
//  SessionDetailView.swift
//  Mood Pomodoro
//

import SwiftUI
import Charts

struct SessionDetailView: View {
    let session: FocusSession

    private var trajectory: [(minutes: Double, mood: Mood)] { AnalyticsService.sessionTrajectory(session) }

    var body: some View {
        ZStack {
            ForestBackdrop()

            ScrollView {
                VStack(spacing: 16) {
                    if trajectory.count >= 2 {
                        trajectoryCard
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.timelineEntries) { entry in
                            TimelineRow(entry: entry)
                        }
                    }
                    .padding(20)
                    .parchmentCard()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.activity)
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }

    private var trajectoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Состояние во время сессии")
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
                        AxisValueLabel("\(minutes)м").font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(18)
        .parchmentCard()
    }
}
