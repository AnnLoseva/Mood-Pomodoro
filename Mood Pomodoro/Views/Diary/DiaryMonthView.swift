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
    /// Read from the local-only health store, not from the CloudKit
    /// container the rest of the month comes from.
    let sleep: [SleepSessionSummary]
    /// Regular width (iPad) lays the cards out two-up instead of stacking.
    let isWide: Bool
    let onSelectDay: (Date) -> Void

    var body: some View {
        // The calendar stays even in an empty month: it's also how the user
        // gets to a past day to fill in something she forgot.
        if summary.isEmpty && summary.supportStats.isEmpty && sleep.isEmpty && !summary.days.contains(where: \.isPeriodDay) {
            VStack(spacing: 16) {
                calendarCard
                emptyCard
            }
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
                if !summary.emotionCounts.isEmpty { emotionsCard }
                if !summary.food.isEmpty { foodCard }
                if let sleepStats { sleepCard(sleepStats) }
                if !summary.supportStats.isEmpty { supportCard }
                factorsCard
            }
        } else {
            VStack(spacing: 16) {
                calendarCard
                moodCard
                studyCard
                if !summary.emotionCounts.isEmpty { emotionsCard }
                if !summary.food.isEmpty { foodCard }
                if let sleepStats { sleepCard(sleepStats) }
                if !summary.supportStats.isEmpty { supportCard }
                factorsCard
                cycleCard
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            MoodImage(mood: .neutral, size: 64)
            Text(L("В этом месяце пока пусто", "Nothing this month yet"))
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("Картина месяца соберётся сама из check-in'ов и сессий. Забытое можно добавить задним числом — нажми на день.", "The month's picture builds itself from check-ins and sessions. Anything you forgot can be added afterwards — tap a day."))
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }

    private var calendarCard: some View {
        DiaryCard(title: L("Календарь", "Calendar"), subtitle: L("Цвет — среднее настроение дня", "Color = the day's average mood")) {
            VStack(alignment: .leading, spacing: 14) {
                MonthCalendarGrid(days: summary.days, onSelectDay: onSelectDay)
                MoodColorLegend()
            }
        }
    }

    private var supportCard: some View {
        DiaryCard(title: L("💊 Ежедневная поддержка", "💊 Daily support")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summary.supportStats) { stat in
                    HStack(spacing: 10) {
                        Text(stat.status.glyph)
                            .font(.lora(15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.status.label)
                                .font(.lora(14))
                                .foregroundStyle(AppTheme.ink)
                            Text(L("\(stat.dayCount) дн.", "\(stat.dayCount) d"))
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        Spacer(minLength: 8)
                        if stat.hasEnoughData, let average = stat.averageMood {
                            Circle()
                                .fill(MoodColorScale.color(for: average))
                                .frame(width: 12, height: 12)
                            Text(String(format: "%.1f", average))
                                .font(.lora(14, weight: .semibold))
                                .foregroundStyle(AppTheme.forest)
                        } else {
                            Text(stat.checkInCount == 0 ? L("нет check-in", "no check-ins") : "\(stat.checkInCount) check-in")
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
                DiaryNote(text: L("Среднее настроение в дни с такой отметкой — наблюдение по твоим данным, не вывод о действии поддержки. Дни без отметки сюда не входят.", "Average mood on days with this mark — an observation from your own data, not a conclusion about what the support does. Days without a mark aren't included."))
            }
        }
    }

    private var sleepStats: SleepPeriodStatistics? {
        guard let first = sleep.first?.day,
              let interval = Calendar.current.dateInterval(of: .month, for: first)
        else { return nil }
        return AnalyticsService.sleepStatistics(sessions: sleep, in: interval)
    }

    /// The month's nights, as recorded. Averages and extremes — no score, no
    /// target, and nothing that calls a night good or bad.
    private func sleepCard(_ stats: SleepPeriodStatistics) -> some View {
        DiaryCard(title: L("🌙 Сон", "🌙 Sleep")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    stat(
                        title: L("Средний сон", "Average sleep"),
                        value: stats.averageSleep.map(DurationFormatting.compact) ?? "—"
                    )
                    stat(title: L("Ночей с данными", "Nights with data"), value: "\(stats.nightCount)")
                }
                if let shortest = stats.shortest, let longest = stats.longest, stats.nightCount > 1 {
                    HStack(spacing: 18) {
                        stat(
                            title: L("Самая короткая", "Shortest"),
                            value: DurationFormatting.compact(shortest.totalSleep)
                        )
                        stat(
                            title: L("Самая длинная", "Longest"),
                            value: DurationFormatting.compact(longest.totalSleep)
                        )
                    }
                }
                if stats.points.count >= 2 {
                    Divider().background(AppTheme.border)
                    sleepChart(stats.points)
                }
                if stats.napCount > 0 {
                    Divider().background(AppTheme.border)
                    HStack(spacing: 18) {
                        stat(title: L("Дневной сон", "Naps"), value: "\(stats.napCount)")
                        stat(
                            title: L("Средняя длина", "Average length"),
                            value: stats.averageNap.map(DurationFormatting.compact) ?? "—"
                        )
                    }
                }
                DiaryNote(text: L("Сон читается из Apple Health на этом устройстве. Подробнее — во вкладке «Аналитика».", "Sleep is read from Apple Health on this device. More in the Analytics tab."))
            }
        }
    }

    private func sleepChart(_ points: [SleepDayPoint]) -> some View {
        Chart(points) { point in
            BarMark(
                x: .value("Дата", point.day, unit: .day),
                y: .value("Сон", point.hours)
            )
            .foregroundStyle(SleepStage.core.color)
            .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let hours = value.as(Double.self) {
                    AxisValueLabel {
                        Text(L("\(Int(hours))ч", "\(Int(hours))h"))
                            .font(.lora(10))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
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
        .frame(height: 150)
    }

    /// The month's food, as counts. Nothing here ranks the categories,
    /// scores the month or says how the user "did" — the figures are
    /// observations, and hunger and appetite are always reported apart.
    private var foodCard: some View {
        DiaryCard(title: L("🍽 Еда", "🍽 Food")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    stat(title: L("Приёмов еды", "Meals"), value: "\(summary.food.mealCount)")
                    if let hunger = summary.food.averageHunger {
                        stat(title: L("Средний голод", "Average hunger"), value: String(format: "%.1f", hunger))
                    }
                    if let appetite = summary.food.averageAppetite {
                        stat(title: L("Средний аппетит", "Average appetite"), value: String(format: "%.1f", appetite))
                    }
                }

                if !summary.food.categoryCounts.isEmpty {
                    Divider().background(AppTheme.border)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Категории еды", "Food categories"))
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        ForEach(summary.food.categoryCounts) { item in
                            countRow(
                                label: item.category.label,
                                count: item.count,
                                imageName: item.category.imageName
                            )
                        }
                    }
                }

                if !summary.food.treats.isEmpty {
                    Divider().background(AppTheme.border)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Вредная еда", "Junk / treat"))
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        ForEach(summary.food.treats.byType, id: \.type) { item in
                            countRow(label: "\(item.type.emoji) \(item.type.label)", count: item.count)
                        }
                        if !summary.food.treats.byAmount.isEmpty {
                            Text(L("Количество", "How much"))
                                .font(.lora(13))
                                .foregroundStyle(AppTheme.inkSoft)
                                .padding(.top, 2)
                            ForEach(summary.food.treats.byAmount, id: \.amount) { item in
                                countRow(label: item.amount.label, count: item.count)
                            }
                        }
                    }
                }

                if let before = summary.food.averageHungerBeforeMeals {
                    DiaryNote(text: L(
                        "Средний голод перед едой: \(String(format: "%.1f", before)) / 5 — по \(summary.food.mealsWithHungerBefore) записям, где голод был отмечен незадолго до еды.",
                        "Average hunger before meals: \(String(format: "%.1f", before)) / 5 — from \(summary.food.mealsWithHungerBefore) entries where hunger was recorded shortly before eating."
                    ))
                }
                DiaryNote(text: L("Это счётчики твоих записей, а не оценка питания. Подробнее — во вкладке «Аналитика».", "These are counts of your own entries, not an assessment of how you eat. More in the Analytics tab."))
            }
        }
    }

    private func countRow(label: String, count: Int, imageName: String? = nil) -> some View {
        HStack(spacing: 10) {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
            }
            Text(label)
                .font(.lora(14))
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.lora(15, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.forest)
        }
    }

    private var moodCard: some View {
        DiaryCard(title: L("🌿 Состояние", "🌿 Mood")) {
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

    /// How often each feeling showed up this month — a count of entries,
    /// never a mood score or a verdict on the month.
    private var emotionsCard: some View {
        DiaryCard(title: L("🎭 Эмоции", "🎭 Emotions")) {
            VStack(alignment: .leading, spacing: 14) {
                EmotionCountRows(counts: summary.emotionCounts)
                DiaryNote(text: L(
                    "Как часто и что ты чувствовала за месяц — счётчик твоих отметок, а не оценка настроения.",
                    "How often and what you felt this month — a count of your own entries, not a mood score."
                ))
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
        DiaryCard(title: L("🌿 Занятия", "🌿 Activities")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    stat(title: L("Всего активно", "Total active"), value: DurationFormatting.compact(summary.totalActiveDuration))
                    stat(title: L("Сессий", "Sessions"), value: "\(summary.sessionCount)")
                }
                if summary.activities.isEmpty {
                    DiaryNote(text: L("Сессий в этом месяце пока не было.", "No sessions this month yet."))
                } else {
                    Divider().background(AppTheme.border)
                    VStack(spacing: 12) {
                        ForEach(summary.sessionTypes) { item in
                        Text("\(SessionType.label(for: item.type)) · \(item.sessionCount) · \(DurationFormatting.compact(item.activeDuration))")
                            .font(.lora(13)).foregroundStyle(AppTheme.ink)
                    }
                    ForEach(summary.activities) { activity in
                            ActivityStatRow(stats: activity)
                        }
                    }
                    DiaryNote(text: L("Это твои наблюдения за месяц, а не оценка занятий.", "These are your observations for the month, not a grade of your work."))
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
        return DiaryCard(title: L("☕ Факторы", "☕ Factors")) {
            if categories.isEmpty {
                DiaryNote(text: L("Пока нет условий, записанных вместе с check-in'ами.", "No conditions recorded with check-ins yet."))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(categories) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(category.categoryIcon) \(Ldata(category.categoryName))")
                                .font(.lora(14, weight: .medium))
                                .foregroundStyle(AppTheme.inkSoft)
                            ForEach(topOptions(of: category)) { option in
                                factorRow(option)
                            }
                        }
                    }
                    DiaryNote(text: L("Так это выглядело в твоих наблюдениях — не вывод о причинах.", "This is how it looked in your observations — not a conclusion about causes."))
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
            Text(Ldata(option.optionName))
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
        DiaryCard(title: L("🌸 Цикл", "🌸 Cycle")) {
            if summary.cycleBuckets.isEmpty {
                DiaryNote(text: L("Цикл в этом месяце не отмечен.", "No cycle recorded this month."))
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
                                Text(bucket.checkInCount == 0 ? L("нет данных", "no data") : "\(bucket.checkInCount) check-in")
                                    .font(.lora(12))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                    }
                    DiaryNote(text: L("Просто наблюдения по дням цикла — без медицинских выводов.", "Just observations by cycle day — no medical conclusions."))
                }
            }
        }
    }
}

/// Month grid: one colored cell per day, the color being the day's average
/// mood on the green→red scale — dense enough to read a whole month at a
/// glance, where tiny illustrations weren't. A day without mood data is
/// parchment with an outline: absence of data is never shown as a mood.
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 40)
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
        let isToday = calendar.isDateInToday(day.date)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Text("\(calendar.component(.day, from: day.date))")
            .font(.lora(13, weight: day.hasMoodData ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(numberColor(for: day))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(shape.fill(fill(for: day)))
            .overlay(
                shape.stroke(
                    isToday ? AppTheme.ink.opacity(0.8) : (day.hasMoodData ? Color.clear : AppTheme.border),
                    lineWidth: isToday ? 2 : 1
                )
            )
            .overlay(alignment: .bottom) {
                HStack(spacing: 4) {
                    if day.supportStatus == .notTaken {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.black).padding(2).background(.white, in: Circle())
                    }
                    if day.isPeriodDay { Circle().fill(.red).frame(width: 6, height: 6).overlay(Circle().stroke(.white, lineWidth: 0.75)) }
                }.frame(height: 12).padding(.bottom, 1)
            }
            .contentShape(shape)
            .accessibilityLabel(accessibilityText(for: day))
    }

    private func fill(for day: DayMoodSummary) -> Color {
        guard let average = day.averageMood else { return AppTheme.chipFill }
        return MoodColorScale.color(for: average)
    }

    private func numberColor(for day: DayMoodSummary) -> Color {
        guard let average = day.averageMood else { return AppTheme.inkSoft }
        return MoodColorScale.prefersLightText(for: average) ? AppTheme.parchmentCard : AppTheme.ink
    }

    private func accessibilityText(for day: DayMoodSummary) -> String {
        let date = DateFormatting.fullDate(day.date) + ", " + (day.supportStatus?.label ?? L("Не отмечено", "Not recorded")) + (day.isPeriodDay ? L(", менструация", ", period") : "")
        guard let average = day.averageMood else { return L("\(date), нет данных", "\(date), no data") }
        return "\(date), \(Mood.nearest(to: average).label), \(String(format: "%.1f", average)), \(day.checkInCount) check-in"
    }

    /// Weekday headers rotated to the user's locale (Mon-first in Russian).
    private var weekdaySymbols: [String] {
        var localized = calendar
        localized.locale = AppLanguage.current.locale
        let symbols = localized.shortWeekdaySymbols
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

/// Swatches for the calendar's scale, plus the "нет данных" outline.
struct MoodColorLegend: View {
    var body: some View {
        FlowLayout(spacing: 10) {
            Text(L("× Не принято · 🔴 Менструация", "× Not taken · 🔴 Period")).font(.lora(11))
            ForEach(MoodColorScale.legend, id: \.mood) { item in
                swatch(label: item.mood.label) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(item.color)
                }
            }
            swatch(label: L("Нет данных", "No data")) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppTheme.chipFill)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
            }
        }
    }

    private func swatch<Shape: View>(label: String, @ViewBuilder shape: () -> Shape) -> some View {
        HStack(spacing: 5) {
            shape().frame(width: 14, height: 14)
            Text(label)
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }
}
