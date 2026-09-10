//
//  AnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData
import Charts

/// Deliberately minimal for the MVP: mood distribution, top reasons, and a
/// few summary numbers. Room to grow (fatigue-over-time, per-activity
/// breakdowns) once there's enough data to make that useful.
struct AnalyticsView: View {
    @Query private var sessions: [FocusSession]

    private var finishedSessions: [FocusSession] {
        sessions.filter { !$0.isActive && $0.endDate != nil }
    }

    private var allCheckIns: [CheckIn] {
        finishedSessions.flatMap(\.checkIns)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()

                if allCheckIns.isEmpty {
                    VStack(spacing: 10) {
                        MoodImage(mood: .neutral, size: 72)
                        Text("Пока мало данных")
                            .font(.lora(19, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Аналитика появится после нескольких сессий")
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .parchmentCard()
                    .padding(.horizontal, 32)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Распределение состояния")
                                    .font(.lora(16, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Chart(moodCounts, id: \.mood) { item in
                                    BarMark(
                                        x: .value("Настроение", item.mood.rawValue),
                                        y: .value("Количество", item.count)
                                    )
                                    .foregroundStyle(AppTheme.forest)
                                    .cornerRadius(6)
                                }
                                .chartXAxis {
                                    AxisMarks { value in
                                        if let raw = value.as(String.self), let mood = Mood(rawValue: raw) {
                                            AxisValueLabel {
                                                MoodImage(mood: mood, size: 22)
                                            }
                                        }
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { _ in
                                        AxisGridLine().foregroundStyle(AppTheme.border)
                                        AxisValueLabel().font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                                    }
                                }
                                .frame(height: 180)
                            }
                            .padding(18)
                            .parchmentCard()

                            if !topReasons.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Частые причины")
                                        .font(.lora(16, weight: .semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    ForEach(topReasons, id: \.reason) { item in
                                        HStack {
                                            Text(item.reason)
                                                .font(.lora(14))
                                                .foregroundStyle(AppTheme.ink)
                                            Spacer()
                                            Text("\(item.count)")
                                                .font(.lora(14, weight: .medium))
                                                .foregroundStyle(AppTheme.inkSoft)
                                        }
                                    }
                                }
                                .padding(18)
                                .parchmentCard()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Сводка")
                                    .font(.lora(16, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                summaryRow("Сессий завершено", "\(finishedSessions.count)")
                                summaryRow("Средняя длительность", averageDurationText)
                                summaryRow("Всего check-ins", "\(allCheckIns.count)")
                            }
                            .padding(18)
                            .parchmentCard()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Аналитика")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.lora(14))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Text(value)
                .font(.lora(14, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    private var moodCounts: [(mood: Mood, count: Int)] {
        Mood.orderedCases.map { mood in
            (mood, allCheckIns.filter { $0.mood == mood }.count)
        }
    }

    private var topReasons: [(reason: String, count: Int)] {
        let reasons = allCheckIns.compactMap(\.reason)
        let counts = Dictionary(grouping: reasons, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var averageDurationText: String {
        let durations = finishedSessions.compactMap { session -> TimeInterval? in
            guard let end = session.endDate else { return nil }
            return end.timeIntervalSince(session.startDate)
        }
        guard !durations.isEmpty else { return "-" }
        let avg = durations.reduce(0, +) / Double(durations.count)
        return "\(Int(avg) / 60) мин"
    }
}
