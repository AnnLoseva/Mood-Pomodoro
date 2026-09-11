//
//  OverviewAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData
import Charts

struct OverviewAnalyticsView: View {
    @Query private var sessions: [FocusSession]
    @Query private var allCheckIns: [CheckIn]
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]

    @State private var selectedReasonMood: Mood = .veryGood

    private var standaloneCheckIns: [CheckIn] { allCheckIns.filter { $0.session == nil } }

    private var overview: OverviewStatistics {
        AnalyticsService.overview(sessions: sessions, standaloneCheckIns: standaloneCheckIns)
    }
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
                    title: L("Среднее состояние", "Average mood"),
                    value: overview.averageMood.map { String(format: "%.1f / 5", $0) } ?? "—"
                )
                statTile(title: "Check-ins", value: "\(overview.checkInCount)")
            }
            HStack(spacing: 0) {
                statTile(title: L("Сессий", "Sessions"), value: "\(overview.sessionCount)")
                statTile(
                    title: L("Ср. длительность", "Avg. duration"),
                    value: overview.averageSessionDuration.map(formattedMinutes) ?? "—"
                )
            }
            HStack {
                Text(L("Среднее время до 🥲 / 😭", "Avg. time until 🥲 / 😭"))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                Spacer()
                Text(overview.averageTimeToFirstDifficultMood.map(formattedMinutes) ?? L("Недостаточно данных", "Not enough data"))
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
            Text(L("Моё состояние", "My mood"))
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
                        AxisValueLabel(L("\(minutes)м", "\(minutes)m")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
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
            Text(L("Что связано с хорошим состоянием?", "What goes along with a good mood?"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            ForEach(insights) { insight in
                HStack {
                    FactorIconView(icon: insight.icon, iconImageName: insight.iconImageName, size: 20)
                    Text(Ldata(insight.name))
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(String(format: "%+.1f", insight.moodDelta))
                        .font(.lora(14, weight: .semibold))
                        .foregroundStyle(insight.moodDelta >= 0 ? AppTheme.forest : AppTheme.rustDeep)
                }
            }
            Text(L("В твоих наблюдениях — не медицинский вывод.", "From your observations — not a medical conclusion."))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(18)
        .parchmentCard()
    }

    private var reasonsCard: some View {
        let reasons = AnalyticsService.reasonStatistics(
            mood: selectedReasonMood,
            sessions: sessions,
            standaloneCheckIns: standaloneCheckIns
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("Частые причины", "Common reasons"))
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
                Text(L("Недостаточно данных", "Not enough data"))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(reasons.prefix(5)) { reason in
                    HStack {
                        Text(Ldata(reason.reason))
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
    if minutes < 60 { return L("\(minutes) мин", "\(minutes) min") }
    return L("\(minutes / 60)ч \(minutes % 60)м", "\(minutes / 60)h \(minutes % 60)m")
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
