//
//  SleepAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData
import Charts

/// "Сон" in Аналитика: the nights as recorded, and the days that followed
/// them placed alongside.
///
/// Every sentence on this screen is observational on purpose. The app does
/// not say short sleep lowered anything, does not call a night poor, does
/// not score deep sleep or REM, and never names a sleep disorder — it shows
/// what was recorded, with the number of observations behind each figure,
/// and lets the user draw her own conclusions.
struct SleepAnalyticsView: View {
    @Environment(SleepStore.self) private var sleepStore

    @Query private var checkIns: [CheckIn]
    @Query private var sessions: [FocusSession]
    @Query private var hungerEntries: [HungerEntry]
    @Query private var foodEntries: [FoodEntry]
    @Query(sort: \CycleEntry.date, order: .reverse) private var cycleEntries: [CycleEntry]

    private let calendar = Calendar.current

    /// All time, like the other Аналитика sections; the month-by-month view
    /// lives in Дневник.
    private var interval: DateInterval? {
        let days = sleepStore.sessions.map(\.day)
        guard let first = days.min(), let last = days.max() else { return nil }
        return DateInterval(start: first, end: last.addingTimeInterval(24 * 60 * 60))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let interval, let stats = AnalyticsService.sleepStatistics(
                    sessions: sleepStore.sessions,
                    in: interval,
                    calendar: calendar
                ) {
                    overviewCard(stats)
                    if stats.hasStageDetail { stagesCard(stats) }
                    associationsCard(interval)
                    deepSleepCard(interval)
                    cycleCard(interval)
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Cards

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("🌙")
                .font(.system(size: 44))
            Text(L("Данных о сне пока нет", "No sleep data yet"))
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(sleepStore.isHealthKitEnabled
                 ? L("Apple Health подключён, но записей о сне за доступный период не нашлось.", "Apple Health is connected, but no sleep was found for the available period.")
                 : L("Подключить Apple Health или добавить сон вручную можно в Дневнике, в карточке «Сон».", "You can connect Apple Health, or add sleep by hand, from the Sleep card in the Diary."))
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }

    private func overviewCard(_ stats: SleepPeriodStatistics) -> some View {
        DiaryCard(title: L("🌙 Сон", "🌙 Sleep")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    tile(
                        title: L("Средний сон", "Average sleep"),
                        value: stats.averageSleep.map(DurationFormatting.compact) ?? "—"
                    )
                    tile(title: L("Ночей с данными", "Nights with data"), value: "\(stats.nightCount)")
                }
                if let shortest = stats.shortest, let longest = stats.longest, stats.nightCount > 1 {
                    Divider().background(AppTheme.border)
                    extremeRow(L("Самая короткая ночь", "Shortest night"), session: shortest)
                    extremeRow(L("Самая длинная ночь", "Longest night"), session: longest)
                }
                if stats.napCount > 0 {
                    Divider().background(AppTheme.border)
                    HStack(spacing: 18) {
                        tile(title: L("Дневной сон", "Naps"), value: "\(stats.napCount)")
                        tile(
                            title: L("Средняя длина", "Average length"),
                            value: stats.averageNap.map(DurationFormatting.compact) ?? "—"
                        )
                    }
                }
                if stats.points.count >= 2 {
                    Divider().background(AppTheme.border)
                    chart(stats.points)
                }
            }
        }
    }

    private func stagesCard(_ stats: SleepPeriodStatistics) -> some View {
        DiaryCard(
            title: L("Стадии сна", "Sleep stages"),
            subtitle: L("В среднем за ночь · по \(stats.stagedNightCount) ночам с подробными стадиями", "Average per night · from \(stats.stagedNightCount) nights with detailed stages")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                stageRow(.deep, average: stats.averageDeep)
                stageRow(.rem, average: stats.averageREM)
                stageRow(.core, average: stats.averageCore)
                stageRow(.awake, average: stats.averageAwake)
                DiaryNote(text: L("Это просто то, что записали часы. Приложение не оценивает стадии сна и не делает из них выводов о здоровье.", "This is simply what the watch recorded. The app doesn't rate sleep stages or draw health conclusions from them."))
            }
        }
    }

    private func associationsCard(_ interval: DateInterval) -> some View {
        let groups = AnalyticsService.sleepAssociations(
            sessions: sleepStore.sessions,
            checkIns: checkIns,
            hungerEntries: hungerEntries,
            foodEntries: foodEntries,
            focusSessions: sessions,
            in: interval,
            calendar: calendar
        )
        return Group {
            if !groups.isEmpty {
                DiaryCard(
                    title: L("Сон и день после", "Sleep and the day after"),
                    subtitle: L("Как выглядели дни после ночей разной длины", "What the days after nights of different lengths looked like")
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            associationBlock(group)
                        }
                        DiaryNote(text: L("Это совпадения в твоих записях, а не причина и следствие: приложение не знает, что на что повлияло.", "These are co-occurrences in your own entries, not cause and effect: the app doesn't know what affected what."))
                    }
                }
            }
        }
    }

    private func deepSleepCard(_ interval: DateInterval) -> some View {
        let groups = AnalyticsService.deepSleepAssociations(
            sessions: sleepStore.sessions,
            checkIns: checkIns,
            focusSessions: sessions,
            in: interval,
            calendar: calendar
        )
        return Group {
            if !groups.isEmpty {
                DiaryCard(
                    title: L("Глубокий сон", "Deep sleep"),
                    subtitle: L("Сравнение с твоей же обычной ночью, а не с нормой", "Compared with your own usual night, not with a norm")
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            associationBlock(group)
                        }
                        DiaryNote(text: L("Ночи разделены по твоей собственной медиане. Никакой «нормы» глубокого сна приложение не знает и не применяет.", "Nights are split at your own median. The app knows no “normal” amount of deep sleep and applies none."))
                    }
                }
            }
        }
    }

    private func cycleCard(_ interval: DateInterval) -> some View {
        let buckets = AnalyticsService.sleepByCycleStretch(
            sessions: sleepStore.sessions,
            cycleEntries: cycleEntries,
            in: interval,
            calendar: calendar
        )
        return Group {
            if !buckets.isEmpty {
                DiaryCard(title: L("🌸 Сон по дням цикла", "🌸 Sleep by cycle day")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(buckets) { bucket in
                            HStack(spacing: 10) {
                                Text(bucket.label)
                                    .font(.lora(14))
                                    .foregroundStyle(AppTheme.ink)
                                Spacer(minLength: 8)
                                if bucket.hasEnoughData {
                                    Text(DurationFormatting.compact(bucket.averageSleep))
                                        .font(.lora(15, weight: .semibold))
                                        .foregroundStyle(AppTheme.forest)
                                } else {
                                    Text(L("мало данных", "little data"))
                                        .font(.lora(12))
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                                Text("(\(bucket.nightCount))")
                                    .font(.lora(11).monospacedDigit())
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                        DiaryNote(text: L("Просто наблюдения по дням цикла — без медицинских выводов.", "Just observations by cycle day — no medical conclusions."))
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func associationBlock(_ group: SleepAssociationGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.label)
                    .font(.lora(14, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 8)
                Text(countLabel(group.dayCount, ru: ("день", "дня", "дней"), en: ("day", "days")))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            if group.hasEnoughData {
                FlowLayout(spacing: 12) {
                    figure(L("настроение", "mood"), group.averageMood, group.moodCount, AppTheme.forest)
                    figure(L("силы", "energy"), group.averageEnergy, group.energyCount, DayMetric.energy.color)
                    figure(L("мотивация", "motivation"), group.averageMotivation, group.motivationCount, DayMetric.motivation.color)
                    if group.hungerCount > 0 {
                        figure(L("голод", "hunger"), group.averageHunger, group.hungerCount, AppTheme.moss)
                    }
                    if group.appetiteCount > 0 {
                        figure(L("аппетит", "appetite"), group.averageAppetite, group.appetiteCount, AppTheme.rust)
                    }
                    if group.studyDuration > 0 {
                        HStack(spacing: 4) {
                            Text(L("учёба", "study"))
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                            Text(DurationFormatting.compact(group.studyDuration / Double(group.dayCount)))
                                .font(.lora(14, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                    if group.treatCount > 0 {
                        HStack(spacing: 4) {
                            Text("🍫")
                            Text("\(group.treatCount)")
                                .font(.lora(14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
            } else {
                Text(L("Недостаточно данных — таких ночей пока мало.", "Not enough data — there have been few nights like this so far."))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private func figure(_ label: String, _ average: Double?, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(average.map { String(format: "%.1f", $0) } ?? "—")
                .font(.lora(14, weight: .semibold).monospacedDigit())
                .foregroundStyle(average == nil ? AppTheme.inkSoft : color)
            if count > 0 {
                Text("(\(count))")
                    .font(.lora(11).monospacedDigit())
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private func stageRow(_ stage: SleepStage, average: TimeInterval?) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(stage.color)
                .frame(width: 12, height: 12)
            Text(stage.label)
                .font(.lora(14))
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            Text(average.map(DurationFormatting.compact) ?? "—")
                .font(.lora(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func extremeRow(_ title: String, session: SleepSessionSummary) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                Text(DateFormatting.compactDate(session.day))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            Spacer(minLength: 8)
            Text(DurationFormatting.compact(session.totalSleep))
                .font(.lora(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func tile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chart(_ points: [SleepDayPoint]) -> some View {
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
        .frame(height: 160)
    }
}
