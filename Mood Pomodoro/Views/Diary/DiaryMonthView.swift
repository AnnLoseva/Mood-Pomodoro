//
//  DiaryMonthView.swift
//  Mood Pomodoro
//

import SwiftUI
import Charts

/// A month at a glance. Same data as the day screen, just aggregated — and
/// still only ever describing what was observed, never claiming that one
/// thing caused another.
struct DiaryMonthView: View {
    let summary: MonthlySummary
    /// Regular width (iPad) lays the cards out two-up instead of stacking.
    let isWide: Bool
    let onSelectDay: (Date) -> Void

    var body: some View {
        if summary.isEmpty {
            emptyCard
        } else if isWide {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    calendarCard.frame(maxWidth: .infinity)
                    moodCard.frame(maxWidth: .infinity)
                }
                HStack(alignment: .top, spacing: 16) {
                    studyCard.frame(maxWidth: .infinity)
                    cycleCard.frame(maxWidth: .infinity)
                }
                factorsCard
            }
        } else {
            VStack(spacing: 16) {
                calendarCard
                moodCard
                studyCard
                factorsCard
                cycleCard
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            MoodImage(mood: .neutral, size: 64)
            Text("В этом месяце пока пусто")
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Картина месяца соберётся сама из check-in'ов и сессий.")
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }

    private var calendarCard: some View {
        DiaryCard(title: "Календарь") {
            MonthCalendarGrid(days: summary.days, onSelectDay: onSelectDay)
        }
    }

    private var moodCard: some View {
        DiaryCard(title: "🌿 Состояние") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MoodAverageLabel(average: summary.moodStats.average)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(summary.moodStats.checkInCount)")
                            .font(.lora(20, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("check-in")
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }

                MoodDistributionRows(distribution: summary.moodStats.distribution)

                if summary.moodOverTime.count >= 2 {
                    Divider().background(AppTheme.border)
                    monthChart
                }
            }
        }
    }

    private var monthChart: some View {
        Chart(summary.moodOverTime) { point in
            LineMark(
                x: .value("Дата", point.date),
                y: .value("Состояние", point.averageMood)
            )
            .foregroundStyle(AppTheme.forest)
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Дата", point.date),
                y: .value("Состояние", point.averageMood)
            )
            .foregroundStyle(AppTheme.rust)
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let raw = value.as(Int.self),
                   let mood = Mood.orderedCases.first(where: { Int($0.scale) == raw }) {
                    AxisValueLabel { Text(mood.emoji) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(DateFormatting.compactDate(date))
                            .font(.lora(10))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
        }
        .frame(height: 170)
    }

    private var studyCard: some View {
        DiaryCard(title: "📚 Учёба") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    stat(title: "Всего активно", value: DurationFormatting.compact(summary.totalActiveDuration))
                    stat(title: "Сессий", value: "\(summary.sessionCount)")
                }
                if summary.activities.isEmpty {
                    DiaryNote(text: "Сессий в этом месяце пока не было.")
                } else {
                    Divider().background(AppTheme.border)
                    VStack(spacing: 12) {
                        ForEach(summary.activities) { activity in
                            ActivityStatRow(stats: activity)
                        }
                    }
                    DiaryNote(text: "Это твои наблюдения за месяц, а не оценка занятий.")
                }
            }
        }
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var factorsCard: some View {
        let categories = summary.factors.filter { category in
            category.optionStats.contains { $0.checkInCount > 0 }
        }
        return DiaryCard(title: "☕ Факторы") {
            if categories.isEmpty {
                DiaryNote(text: "Пока нет условий, записанных вместе с check-in'ами.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(categories) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(category.categoryIcon) \(category.categoryName)")
                                .font(.lora(14, weight: .medium))
                                .foregroundStyle(AppTheme.inkSoft)
                            ForEach(topOptions(of: category)) { option in
                                factorRow(option)
                            }
                        }
                    }
                    DiaryNote(text: "Так это выглядело в твоих наблюдениях — не вывод о причинах.")
                }
            }
        }
    }

    private func topOptions(of category: FactorCategoryStatistics) -> [FactorOptionStatistics] {
        category.optionStats
            .filter { $0.checkInCount > 0 }
            .sorted { $0.checkInCount > $1.checkInCount }
            .prefix(4)
            .map { $0 }
    }

    private func factorRow(_ option: FactorOptionStatistics) -> some View {
        HStack(spacing: 10) {
            FactorIconView(icon: option.optionIcon, iconImageName: option.optionIconImageName, size: 20)
            Text(option.optionName)
                .font(.lora(14))
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            if option.hasEnoughData, let average = option.averageMood {
                Text(String(format: "%.1f", average))
                    .font(.lora(14, weight: .semibold))
                    .foregroundStyle(AppTheme.forest)
            }
            Text("\(option.checkInCount) check-in")
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    private var cycleCard: some View {
        DiaryCard(title: "🌸 Цикл") {
            if summary.cycleBuckets.isEmpty {
                DiaryNote(text: "Цикл в этом месяце не отмечен.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.cycleBuckets) { bucket in
                        HStack(spacing: 10) {
                            Text(bucket.label)
                                .font(.lora(14))
                                .foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 8)
                            if bucket.hasEnoughData, let average = bucket.averageMood {
                                MoodImage(mood: .nearest(to: average), size: 22)
                                Text(String(format: "%.1f", average))
                                    .font(.lora(14, weight: .semibold))
                                    .foregroundStyle(AppTheme.forest)
                            } else {
                                Text(bucket.checkInCount == 0 ? "нет данных" : "\(bucket.checkInCount) check-in")
                                    .font(.lora(12))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                    }
                    DiaryNote(text: "Просто наблюдения по дням цикла — без медицинских выводов.")
                }
            }
        }
    }
}

/// Month grid: one cell per day, showing the day's mushroom when something
/// was recorded. Empty days stay quietly empty — no gaps to "fill in".
struct MonthCalendarGrid: View {
    let days: [DayMoodSummary]
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }
                ForEach(days) { day in
                    Button {
                        onSelectDay(day.date)
                    } label: {
                        cell(for: day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cell(for day: DayMoodSummary) -> some View {
        VStack(spacing: 1) {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
            if let mood = day.representativeMood {
                MoodImage(mood: mood, size: 22)
            } else {
                Circle()
                    .fill(AppTheme.border.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(calendar.isDateInToday(day.date) ? AppTheme.forest.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(calendar.isDateInToday(day.date) ? AppTheme.forest.opacity(0.5) : Color.clear, lineWidth: 1.25)
        )
    }

    /// Weekday headers rotated to the user's locale (Mon-first in Russian).
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Blank cells before the 1st so it lands under the right weekday.
    private var leadingBlanks: Int {
        guard let first = days.first?.date else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}
