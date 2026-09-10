//
//  OverviewAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData
import Charts

struct OverviewAnalyticsView: View {
    @Query private var sessions: [FocusSession]
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]

    @State private var selectedReasonMood: Mood = .veryGood

    private var overview: OverviewStatistics { AnalyticsService.overview(sessions: sessions) }
    private var trajectory: [MoodTimelinePoint] { AnalyticsService.moodTrajectory(sessions: sessions) }
    private var insights: [FactorInsight] { AnalyticsService.topPositiveFactors(categories: categories, sessions: sessions) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                if trajectory.count >= 2 {
                    trajectoryCard
                }
                if !insights.isEmpty {
                    insightsCard
                }
                reasonsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                statTile(
                    title: "Среднее состояние",
                    value: overview.averageMood.map { String(format: "%.1f / 5", $0) } ?? "—"
                )
                statTile(title: "Check-ins", value: "\(overview.checkInCount)")
            }
            HStack(spacing: 0) {
                statTile(title: "Сессий", value: "\(overview.sessionCount)")
                statTile(
                    title: "Ср. длительность",
                    value: overview.averageSessionDuration.map(formattedMinutes) ?? "—"
                )
            }
            HStack {
                Text("Среднее время до 🥲 / 😭")
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
                Text(overview.averageTimeToFirstDifficultMood.map(formattedMinutes) ?? "Недостаточно данных")
                    .font(.lora(13, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
            }

            if overview.checkInCount > 0 {
                Divider().background(AppTheme.border)
                MoodDistributionChart(distribution: overview.moodDistribution)
                    .frame(height: 150)
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trajectoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Моё состояние")
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            Chart(trajectory) { point in
                LineMark(
                    x: .value("Минуты", point.minuteBucketStart),
                    y: .value("Состояние", point.averageMood)
                )
                .foregroundStyle(AppTheme.forest)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Минуты", point.minuteBucketStart),
                    y: .value("Состояние", point.averageMood)
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
            .frame(height: 180)

            if let observation = AnalyticsService.declineObservation(trajectory: trajectory) {
                Text(observation)
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Что связано с хорошим состоянием?")
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            ForEach(insights) { insight in
                HStack {
                    FactorIconView(icon: insight.icon, iconImageName: insight.iconImageName, size: 20)
                    Text(insight.name)
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(String(format: "%+.1f", insight.moodDelta))
                        .font(.lora(14, weight: .semibold))
                        .foregroundStyle(insight.moodDelta >= 0 ? AppTheme.forest : AppTheme.rustDeep)
                }
            }
            Text("В твоих наблюдениях — не медицинский вывод.")
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(18)
        .parchmentCard()
    }

    private var reasonsCard: some View {
        let reasons = AnalyticsService.reasonStatistics(mood: selectedReasonMood, sessions: sessions)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Частые причины")
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 8) {
                ForEach(Mood.orderedCases) { mood in
                    Button {
                        selectedReasonMood = mood
                    } label: {
                        Text(mood.emoji)
                            .font(.system(size: 20))
                            .padding(6)
                            .background(
                                Circle().fill(mood == selectedReasonMood ? AppTheme.forest.opacity(0.18) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if reasons.isEmpty {
                Text("Недостаточно данных")
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(reasons.prefix(5)) { reason in
                    HStack {
                        Text(reason.reason)
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(Int((reason.percentage * 100).rounded()))%")
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }
}

private func formattedMinutes(_ interval: TimeInterval) -> String {
    let minutes = Int(interval / 60)
    if minutes < 60 { return "\(minutes) мин" }
    return "\(minutes / 60)ч \(minutes % 60)м"
}

struct MoodDistributionChart: View {
    let distribution: MoodDistribution

    var body: some View {
        Chart(Mood.orderedCases) { mood in
            BarMark(
                x: .value("Настроение", mood.rawValue),
                y: .value("Количество", distribution.counts[mood] ?? 0)
            )
            .foregroundStyle(AppTheme.forest)
            .cornerRadius(6)
        }
        .chartXAxis {
            AxisMarks { value in
                if let raw = value.as(String.self), let mood = Mood(rawValue: raw) {
                    AxisValueLabel { MoodImage(mood: mood, size: 20) }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(AppTheme.border)
                AxisValueLabel().font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
            }
        }
    }
}
