//
//  FoodAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// "Еда" in Аналитика: everything recorded about food, hunger and appetite,
/// over all time.
///
/// Three things this screen refuses to do, and the reason the copy is worded
/// the way it is:
/// * It never mixes hunger and appetite into one number. They are two
///   scales about two different things and are always shown side by side.
/// * It never says one thing caused another. Meals and moods are linked by
///   nothing but the clock, so the wording is always "рядом с этим у тебя
///   чаще встречалось…".
/// * It never grades. No score, no streak, no "хороший / плохой день
///   питания", no calories and nothing that suggests eating differently —
///   the categories are the user's own labels on her own records.
struct FoodAnalyticsView: View {
    @Query private var foodEntries: [FoodEntry]
    @Query private var hungerEntries: [HungerEntry]
    @Query private var checkIns: [CheckIn]
    @Query private var sessions: [FocusSession]
    @Query(sort: \CycleEntry.date, order: .reverse) private var cycleEntries: [CycleEntry]

    private let calendar = Calendar.current

    /// All time — the same scope the other Аналитика sections use. The
    /// month-by-month view lives in Дневник.
    private var summary: FoodMonthSummary {
        let dates = foodEntries.map(\.eventDate) + hungerEntries.map(\.eventDate)
        guard let first = dates.min(), let last = dates.max() else { return .empty }
        return AnalyticsService.foodMonthSummary(
            in: DateInterval(start: first, end: last.addingTimeInterval(1)),
            foodEntries: foodEntries,
            hungerEntries: hungerEntries,
            checkIns: checkIns,
            sessions: sessions,
            cycleEntries: cycleEntries,
            calendar: calendar
        )
    }

    var body: some View {
        ScrollView {
            let summary = summary
            VStack(spacing: 16) {
                if summary.isEmpty {
                    emptyCard
                } else {
                    if summary.hasHungerOrAppetite { hungerAppetiteCard(summary) }
                    if let grid = hungerAppetiteGrid, grid.total >= AnalyticsService.minimumSampleSize {
                        gridCard(grid)
                    }
                    if summary.mealCount > 0 { foodCard(summary) }
                    if !summary.byDayPart.isEmpty {
                        groupCard(
                            title: L("🕰 По времени суток", "🕰 By time of day"),
                            groups: summary.byDayPart
                        )
                    }
                    if !summary.aroundMeals.isEmpty { aroundMealsCard(summary) }
                    if !summary.byMood.isEmpty {
                        groupCard(
                            title: L("🙂 Рядом с настроением", "🙂 Alongside mood"),
                            groups: summary.byMood,
                            footnote: L("Голод и аппетит рядом по времени с отметкой настроения — совпадение по часам, не влияние одного на другое.", "Hunger and appetite recorded close in time to a mood entry — co-occurrence on the clock, not one affecting the other.")
                        )
                    }
                    if !summary.byActivity.isEmpty {
                        groupCard(
                            title: L("🌿 Во время занятий", "🌿 During activities"),
                            groups: summary.byActivity,
                            footnote: L("Только записи, сделанные во время сессии. Сделанные вне занятий сюда не входят.", "Only entries made while a session was running. Anything recorded outside a session isn't included here.")
                        )
                    }
                    if !summary.byCycleStretch.isEmpty {
                        groupCard(
                            title: L("🌸 По дням цикла", "🌸 By cycle day"),
                            groups: summary.byCycleStretch,
                            footnote: L("Просто наблюдения по дням цикла — без медицинских выводов.", "Just observations by cycle day — no medical conclusions.")
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Cards

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("🍽")
                .font(.system(size: 44))
            Text(L("Про еду пока ничего не записано", "Nothing recorded about food yet"))
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("Записи о еде, голоде и аппетите добавляются в Дневнике — через «Добавить».", "Food, hunger and appetite entries are added in the Diary, under “Add”."))
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }

    private func hungerAppetiteCard(_ summary: FoodMonthSummary) -> some View {
        DiaryCard(title: L("🍎 Голод и аппетит", "🍎 Hunger and appetite")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    scaleTile(
                        title: L("Средний голод", "Average hunger"),
                        average: summary.averageHunger,
                        count: summary.hungerCount,
                        color: AppTheme.forest,
                        level: HungerLevel.self
                    )
                    scaleTile(
                        title: L("Средний аппетит", "Average appetite"),
                        average: summary.averageAppetite,
                        count: summary.appetiteCount,
                        color: AppTheme.rust,
                        level: AppetiteLevel.self
                    )
                }
                if let before = summary.averageHungerBeforeMeals {
                    Divider().background(AppTheme.border)
                    HStack(spacing: 10) {
                        Text(L("Голод перед едой", "Hunger before meals"))
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f / 5", before))
                            .font(.lora(15, weight: .semibold))
                            .foregroundStyle(AppTheme.forest)
                        Text("(\(summary.mealsWithHungerBefore))")
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    DiaryNote(text: L("Считается по записям, где голод был отмечен не больше чем за полтора часа до еды. Остальные приёмы еды сюда не входят.", "Counted from entries where hunger was recorded no more than an hour and a half before eating. Other meals aren't included."))
                }
                DiaryNote(text: L("Голод — насколько телу нужна еда. Аппетит — насколько хочется есть. Это разные шкалы, и они никогда не складываются в одну.", "Hunger is how much your body needs food. Appetite is how much you feel like eating. They are different scales and are never merged into one."))
            }
        }
    }

    /// The 5×5 "goes with" grid: how often each hunger value was recorded
    /// with each appetite value. A scatter would just stack points on 25
    /// positions; a count per cell says the same thing and stays readable.
    private func gridCard(_ grid: HungerAppetiteGrid) -> some View {
        DiaryCard(
            title: L("Голод рядом с аппетитом", "Hunger alongside appetite"),
            subtitle: L("Сколько раз встречалась каждая пара · всего \(grid.total)", "How often each pair came up · \(grid.total) in total")
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(AppetiteLevel.orderedCases), id: \.id) { appetite in
                    HStack(spacing: 4) {
                        Text("\(Int(appetite.scale))")
                            .font(.lora(11).monospacedDigit())
                            .foregroundStyle(AppTheme.inkSoft)
                            .frame(width: 16, alignment: .trailing)
                        ForEach(Array(HungerLevel.orderedCases.reversed()), id: \.id) { hunger in
                            let count = grid.count(hunger: hunger, appetite: appetite)
                            Text(count == 0 ? "" : "\(count)")
                                .font(.lora(12, weight: .medium).monospacedDigit())
                                .foregroundStyle(count == 0 ? AppTheme.inkSoft : AppTheme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(AppTheme.forest.opacity(grid.share(hunger: hunger, appetite: appetite) * 0.7))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        }
                    }
                }
                HStack(spacing: 4) {
                    Color.clear.frame(width: 16, height: 1)
                    ForEach(Array(HungerLevel.orderedCases.reversed()), id: \.id) { hunger in
                        Text("\(Int(hunger.scale))")
                            .font(.lora(11).monospacedDigit())
                            .foregroundStyle(AppTheme.inkSoft)
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 6) {
                    LevelImage(level: HungerLevel.veryHungry, size: 20)
                    Text(L("→ голод", "→ hunger"))
                    Spacer()
                    Text(L("↑ аппетит", "↑ appetite"))
                    LevelImage(level: AppetiteLevel.veryHigh, size: 20)
                }
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
                DiaryNote(text: L("Углы — это про то, что голод и аппетит расходятся: например, голодна, но есть не хочется.", "The corners are where hunger and appetite pull apart — hungry but not wanting to eat, for instance."))
            }
        }
    }

    private func foodCard(_ summary: FoodMonthSummary) -> some View {
        DiaryCard(title: L("🍽 Записи о еде", "🍽 Food entries")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(L("Всего", "In total"))
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 8)
                    Text("\(summary.mealCount)")
                        .font(.lora(18, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
                Divider().background(AppTheme.border)
                ForEach(summary.categoryCounts) { item in
                    countRow(label: item.category.label, count: item.count, imageName: item.category.imageName)
                }
                if !summary.treats.isEmpty {
                    Divider().background(AppTheme.border)
                    Text(L("Вредная еда", "Junk / treat"))
                        .font(.lora(13, weight: .medium))
                        .foregroundStyle(AppTheme.inkSoft)
                    ForEach(summary.treats.byType, id: \.type) { item in
                        countRow(label: "\(item.type.emoji) \(item.type.label)", count: item.count)
                    }
                    ForEach(summary.treats.byAmount, id: \.amount) { item in
                        countRow(label: item.amount.label, count: item.count)
                    }
                }
                if !summary.fullness.isEmpty {
                    Divider().background(AppTheme.border)
                    Text(L("Сытость после еды", "How full afterwards"))
                        .font(.lora(13, weight: .medium))
                        .foregroundStyle(AppTheme.inkSoft)
                    ForEach(summary.fullness) { item in
                        countRow(label: "\(item.fullness.emoji) \(item.fullness.label)", count: item.count)
                    }
                }
                DiaryNote(text: L("Это счётчики твоих собственных пометок. Приложение не считает калории и не оценивает, как ты ешь.", "These are counts of your own labels. The app doesn't count calories and doesn't judge how you eat."))
            }
        }
    }

    /// Mood, energy and hunger recorded near meals of each category. Never
    /// phrased as an effect — only as what tended to be written down nearby.
    private func aroundMealsCard(_ summary: FoodMonthSummary) -> some View {
        DiaryCard(
            title: L("Рядом с едой", "Around meals"),
            subtitle: L("Что чаще встречалось в записях в пределах полутора часов", "What tended to be recorded within an hour and a half")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(summary.aroundMeals) { observation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(observation.category.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 26, height: 26)
                            Text(observation.category.label)
                                .font(.lora(14, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 8)
                            Text(countLabel(observation.mealCount, ru: ("запись", "записи", "записей"), en: ("entry", "entries")))
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        observationRow(
                            label: L("Голод до", "Hunger before"),
                            average: observation.averageHungerBefore,
                            count: observation.hungerSampleCount,
                            hasEnough: observation.hasEnoughHunger
                        )
                        observationRow(
                            label: L("Настроение после", "Mood after"),
                            average: observation.averageMoodAfter,
                            count: observation.moodSampleCount,
                            hasEnough: observation.hasEnoughMood
                        )
                        observationRow(
                            label: L("Силы после", "Energy after"),
                            average: observation.averageEnergyAfter,
                            count: observation.energySampleCount,
                            hasEnough: observation.hasEnoughEnergy
                        )
                    }
                }
                DiaryNote(text: L("Это только то, что оказалось записано рядом по времени. Совпадение не значит, что еда на что-то повлияла.", "This is only what happened to be recorded close in time. Things co-occurring doesn't mean the food did anything."))
            }
        }
    }

    private func groupCard(
        title: String,
        groups: [HungerAppetiteGroup],
        footnote: String? = nil
    ) -> some View {
        DiaryCard(title: title) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text([group.emoji, group.label].compactMap { $0 }.joined(separator: " "))
                                .font(.lora(14, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 8)
                            if !group.hasEnoughData {
                                Text(L("мало данных", "little data"))
                                    .font(.lora(12))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                        HStack(spacing: 14) {
                            figure(
                                label: L("голод", "hunger"),
                                average: group.averageHunger,
                                count: group.hungerCount,
                                color: AppTheme.forest
                            )
                            figure(
                                label: L("аппетит", "appetite"),
                                average: group.averageAppetite,
                                count: group.appetiteCount,
                                color: AppTheme.rust
                            )
                            if group.foodCount > 0 {
                                figureText(
                                    label: L("еда", "food"),
                                    value: group.treatCount > 0
                                        ? "\(group.foodCount) · 🍫 \(group.treatCount)"
                                        : "\(group.foodCount)"
                                )
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                if let footnote { DiaryNote(text: footnote) }
            }
        }
    }

    // MARK: - Small pieces

    /// The illustration is the step closest to the average — what the period
    /// actually looked like — and the number under it is a position on the
    /// scale, never a score.
    private func scaleTile<Level: LevelScale>(
        title: String,
        average: Double?,
        count: Int,
        color: Color,
        level: Level.Type
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            HStack(spacing: 8) {
                if let average, let step = Level.closest(to: average) {
                    LevelImage(level: step, size: 38)
                }
                Text(average.map { String(format: "%.1f / 5", $0) } ?? "—")
                    .font(.lora(20, weight: .semibold))
                    .foregroundStyle(average == nil ? AppTheme.inkSoft : color)
            }
            Text(countLabel(count, ru: ("отметка", "отметки", "отметок"), en: ("entry", "entries")))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func figure(label: String, average: Double?, count: Int, color: Color) -> some View {
        figureText(
            label: label,
            value: average.map { String(format: "%.1f", $0) } ?? "—",
            valueColor: average == nil ? AppTheme.inkSoft : color,
            trailing: count > 0 ? "(\(count))" : nil
        )
    }

    private func figureText(
        label: String,
        value: String,
        valueColor: Color = AppTheme.ink,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(14, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueColor)
            if let trailing {
                Text(trailing)
                    .font(.lora(11).monospacedDigit())
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    /// Below the sample threshold the count is shown instead of an average,
    /// rather than implying a precision that isn't there.
    private func observationRow(label: String, average: Double?, count: Int, hasEnough: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
            Spacer(minLength: 8)
            if hasEnough, let average {
                Text(String(format: "%.1f / 5", average))
                    .font(.lora(14, weight: .semibold))
                    .foregroundStyle(AppTheme.forest)
                Text("(\(count))")
                    .font(.lora(11).monospacedDigit())
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                Text(count == 0
                     ? L("нет записей рядом", "nothing recorded nearby")
                     : L("недостаточно данных (\(count))", "not enough data (\(count))"))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
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

    private var hungerAppetiteGrid: HungerAppetiteGrid? {
        let pairs = hungerEntries.compactMap { entry -> (HungerLevel, AppetiteLevel)? in
            guard let hunger = entry.hunger, let appetite = entry.appetite else { return nil }
            return (hunger, appetite)
        }
        return pairs.isEmpty ? nil : HungerAppetiteGrid(pairs: pairs)
    }
}

/// Counts of every (hunger, appetite) pair that was recorded together. Only
/// entries where *both* were answered are in here — a half-answered record
/// has no pair and is left out rather than completed with a guess.
struct HungerAppetiteGrid {
    private var counts: [String: Int] = [:]
    private(set) var total = 0
    private(set) var peak = 0

    init(pairs: [(HungerLevel, AppetiteLevel)]) {
        for (hunger, appetite) in pairs {
            let key = "\(hunger.rawValue)|\(appetite.rawValue)"
            counts[key, default: 0] += 1
            peak = max(peak, counts[key] ?? 0)
            total += 1
        }
    }

    func count(hunger: HungerLevel, appetite: AppetiteLevel) -> Int {
        counts["\(hunger.rawValue)|\(appetite.rawValue)"] ?? 0
    }

    /// 0…1 against the busiest cell, for how dark to draw it.
    func share(hunger: HungerLevel, appetite: AppetiteLevel) -> Double {
        guard peak > 0 else { return 0 }
        return Double(count(hunger: hunger, appetite: appetite)) / Double(peak)
    }
}
