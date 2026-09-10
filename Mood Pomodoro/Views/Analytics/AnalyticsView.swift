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
            Group {
                if allCheckIns.isEmpty {
                    ContentUnavailableView(
                        "Пока мало данных",
                        systemImage: "chart.bar",
                        description: Text("Аналитика появится после нескольких сессий")
                    )
                } else {
                    List {
                        Section("Распределение состояния") {
                            Chart(moodCounts, id: \.mood) { item in
                                BarMark(
                                    x: .value("Настроение", item.mood.emoji),
                                    y: .value("Количество", item.count)
                                )
                                .foregroundStyle(.tint)
                            }
                            .frame(height: 180)
                        }

                        if !topReasons.isEmpty {
                            Section("Частые причины") {
                                ForEach(topReasons, id: \.reason) { item in
                                    HStack {
                                        Text(item.reason)
                                        Spacer()
                                        Text("\(item.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        Section("Сводка") {
                            LabeledContent("Сессий завершено", value: "\(finishedSessions.count)")
                            LabeledContent("Средняя длительность", value: averageDurationText)
                            LabeledContent("Всего check-ins", value: "\(allCheckIns.count)")
                        }
                    }
                }
            }
            .navigationTitle("Аналитика")
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
