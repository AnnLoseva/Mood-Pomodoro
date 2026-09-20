import SwiftUI

/// Питание: meals, satiety and appetite on one 1–5 axis, and — on request —
/// before/after, categories and the hunger × appetite grid.
struct FoodAnalyticsView: View {
    @Bindable var store: AnalyticsStore
    @State private var gridMode = false
    @State private var selectedCell: AnalyticsGridCell?

    var body: some View {
        let snapshot = store.snapshot
        let food = snapshot.food
        let satiety = AnalyticsChartSeries.make(metric: .satiety, days: snapshot.days)
        let appetite = AnalyticsChartSeries.make(metric: .appetite, days: snapshot.days)

        AnalyticsDetailScaffold(title: AnalyticsSection.food.title, store: store) {
            if food.mealCount == 0 && satiety.isEmpty && appetite.isEmpty {
                AnalyticsEmptyCard(
                    title: L("Про еду пока ничего не записано", "Nothing recorded about food yet"),
                    message: L("Добавь приём пищи в Дневнике — через «Добавить».", "Add a meal in the Diary, under Add.")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        AnalyticsStatTile(title: L("Приёмов пищи", "Meals"), value: "\(food.mealCount)")
                        if let treats = food.treatsPerDay {
                            AnalyticsStatTile(title: L("Сладкое и снеки в день", "Treats & snacks a day"), value: String(format: "%.2f", treats))
                        }
                        AnalyticsInfoButton(text: L(
                            "Окно связи еды и состояния: \(Int(food.linkWindowSeconds / 60)) мин. Один приём пищи считается один раз. Отсутствие записи не значит, что еды не было.",
                            "Food–state window: \(Int(food.linkWindowSeconds / 60)) min. Each meal counts once. A missing record does not mean there was no food."
                        ))
                    }
                    AnalyticsMetricChart(series: [satiety, appetite], interval: snapshot.interval, height: 180)
                }
                .padding(16)
                .parchmentCard(padding: 0)

                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(title: AnalyticsRecordKind.meals.title, value: "\(food.mealCount)", route: .records(.meals))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: AnalyticsRecordKind.hunger.title, route: .records(.hunger))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: AnalyticsMetric.satiety.title, route: .metric(.satiety))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: AnalyticsMetric.appetite.title, route: .metric(.appetite))
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)

                if food.mealCount > 0 {
                    AnalyticsDisclosure(L("До и после еды", "Before and after meals")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("настроение до \(analyticsFormat(food.moodBefore.average)) → после \(analyticsFormat(food.moodAfter.average))",
                                   "mood before \(analyticsFormat(food.moodBefore.average)) → after \(analyticsFormat(food.moodAfter.average))"))
                                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                            Text(L("голод до \(analyticsFormat(food.hungerBefore.average)) · насыщение после \(analyticsFormat(food.fullnessAfter.average))",
                                   "hunger before \(analyticsFormat(food.hungerBefore.average)) · fullness after \(analyticsFormat(food.fullnessAfter.average))"))
                                .font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                            Text(L("голод заполнен в \(percent(food.hungerFilledShare)) приёмов · аппетит \(percent(food.appetiteFilledShare)) · насыщение \(percent(food.fullnessFilledShare))",
                                   "hunger filled for \(percent(food.hungerFilledShare)) of meals · appetite \(percent(food.appetiteFilledShare)) · fullness \(percent(food.fullnessFilledShare))"))
                                .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                            AnalyticsReliabilityBadge(confidence: food.hungerBefore.confidence, extra: L("единица: приёмы пищи", "unit: meals"))
                        }
                    }
                }

                if !food.byCategory.isEmpty {
                    AnalyticsDisclosure(L("По категориям еды", "By food category"), summary: "\(food.byCategory.count)") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(food.byCategory) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.label) · \(row.count)").font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                    Text(L("настроение после \(analyticsFormat(row.moodAfter.average)) · голод до \(analyticsFormat(row.hungerBefore.average))",
                                           "mood after \(analyticsFormat(row.moodAfter.average)) · hunger before \(analyticsFormat(row.hungerBefore.average))"))
                                        .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                }
                            }
                        }
                    }
                }

                AnalyticsDisclosure(L("Голод × аппетит", "Hunger × appetite")) { grid(food) }

                if food.impulseFoodDays > 0 {
                    AnalyticsQuietNote(text: L("Дней с импульсом «еда»: \(food.impulseFoodDays). Отсутствие отметки не значит, что импульса не было.",
                                               "Days with a food impulse mark: \(food.impulseFoodDays). A missing mark is not proof there was no impulse."))
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func grid(_ food: AnalyticsFoodSummary) -> some View {
        let cells = food.hungerAppetitePairs
        let total = max(1, cells.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("По горизонтали — аппетит, по вертикали — голод (сильный сверху).", "Across: appetite. Up: hunger (strong at the top)."))
                    .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                Spacer(minLength: 8)
                Button(gridMode ? L("Доли", "Share") : L("Числа", "Counts")) { gridMode.toggle() }
                    .font(.lora(12)).foregroundStyle(AppTheme.forest).frame(minHeight: 44)
            }
            ForEach([5, 4, 3, 2, 1], id: \.self) { hunger in
                HStack(spacing: 4) {
                    Text("\(hunger)").font(.lora(10)).foregroundStyle(AppTheme.inkSoft).frame(width: 14)
                    ForEach([1, 2, 3, 4, 5], id: \.self) { appetite in
                        let count = cells.first { $0.hungerKey == "\(hunger)" && $0.appetiteKey == "\(appetite)" }?.count ?? 0
                        Button {
                            selectedCell = AnalyticsGridCell(hungerKey: "\(hunger)", appetiteKey: "\(appetite)", count: count)
                        } label: {
                            Text(gridMode ? "\(Int((Double(count) / Double(total) * 100).rounded()))%" : "\(count)")
                                .font(.lora(11, weight: .medium)).foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(AnalyticsMetric.appetite.color.opacity(count == 0 ? 0.04 : min(0.55, 0.1 + 0.45 * Double(count) / Double(cells.map(\.count).max() ?? 1))))
                                .overlay(Rectangle().stroke(AppTheme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Голод \(hunger), аппетит \(appetite): \(count)", "Hunger \(hunger), appetite \(appetite): \(count)"))
                    }
                }
            }
            if let selectedCell {
                Text(L("Голод \(selectedCell.hungerKey), аппетит \(selectedCell.appetiteKey): \(selectedCell.count) наблюдений",
                       "Hunger \(selectedCell.hungerKey), appetite \(selectedCell.appetiteKey): \(selectedCell.count) observations"))
                    .font(.lora(12)).foregroundStyle(AppTheme.ink)
            }
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}
