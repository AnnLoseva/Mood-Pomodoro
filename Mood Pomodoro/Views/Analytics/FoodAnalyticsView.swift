import SwiftUI
import Charts

struct FoodAnalyticsView: View {
    let snapshot: AnalyticsSnapshot
    @State private var gridMode = false
    @State private var selectedCell: AnalyticsGridCell?

    var body: some View {
        let food = snapshot.food
        ScrollView {
            LazyVStack(spacing: 16) {
                if food.mealCount == 0 {
                    AnalyticsEmptyCard(
                        title: L("Про еду пока ничего не записано", "Nothing recorded about food yet"),
                        message: L("Добавь приём пищи в Дневнике — через «Добавить».", "Add a meal in the Diary, under Add.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            AnalyticsStatTile(title: L("Приёмов пищи", "Meals"), value: "\(food.mealCount)")
                            AnalyticsStatTile(title: L("Голод заполнен", "Hunger filled"), value: percent(food.hungerFilledShare))
                        }
                        HStack {
                            AnalyticsStatTile(title: L("Аппетит заполнен", "Appetite filled"), value: percent(food.appetiteFilledShare))
                            AnalyticsStatTile(title: L("Насыщение", "Fullness"), value: percent(food.fullnessFilledShare))
                        }
                        Text(L("Окно связи еды и состояния: \(Int(food.linkWindowSeconds / 60)) мин. Один приём пищи считается один раз.", "Food–state window: \(Int(food.linkWindowSeconds / 60)) min. Each meal counts once."))
                            .font(.lora(11))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(18)
                    .parchmentCard()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("До и после еды", "Before and after meals")).font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        Text(L("настроение до \(analyticsFormat(food.moodBefore.average)) → после \(analyticsFormat(food.moodAfter.average))", "mood before \(analyticsFormat(food.moodBefore.average)) → after \(analyticsFormat(food.moodAfter.average))"))
                            .font(.lora(14)).foregroundStyle(AppTheme.ink)
                        Text(L("голод до \(analyticsFormat(food.hungerBefore.average)) · насыщение после \(analyticsFormat(food.fullnessAfter.average))", "hunger before \(analyticsFormat(food.hungerBefore.average)) · fullness after \(analyticsFormat(food.fullnessAfter.average))"))
                            .font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                        AnalyticsReliabilityBadge(confidence: food.hungerBefore.confidence, extra: L("единица: приёмы пищи", "unit: meals"))
                    }
                    .padding(18)
                    .parchmentCard()

                    if !food.byCategory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("По категориям еды", "By food category")).font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            ForEach(food.byCategory) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.label) · \(row.count)")
                                        .font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                    Text(L("настроение после \(analyticsFormat(row.moodAfter.average)) · голод до \(analyticsFormat(row.hungerBefore.average))", "mood after \(analyticsFormat(row.moodAfter.average)) · hunger before \(analyticsFormat(row.hungerBefore.average))"))
                                        .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                }
                            }
                        }
                        .padding(18)
                        .parchmentCard()
                    }

                    if let treats = food.treatsPerDay {
                        Text(L("Сладкое и снеки: \(String(format: "%.2f", treats)) на календарный день периода", "Treats and snacks: \(String(format: "%.2f", treats)) per calendar day of the period"))
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .parchmentCard()
                    }

                    Text(L("Дней с импульсом «еда»: \(food.impulseFoodDays). Отсутствие отметки не значит, что импульса не было.", "Days with a food impulse mark: \(food.impulseFoodDays). A missing mark is not proof there was no impulse."))
                        .font(.lora(13))
                        .foregroundStyle(AppTheme.inkSoft)
                        .padding(18)
                        .parchmentCard()

                    dailyChart
                    grid
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private var dailyChart: some View {
        let days = snapshot.days.filter { $0.hunger != nil || $0.appetite != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Голод и аппетит по дням", "Hunger and appetite by day"))
                .font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
            if days.isEmpty {
                Text(L("Пока нет дневных отметок голода или аппетита.", "No daily hunger or appetite marks yet."))
                    .font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
            } else {
                Chart {
                    ForEach(days) { day in
                        if let hunger = day.hunger {
                            LineMark(x: .value("d", day.day), y: .value(L("Голод", "Hunger"), hunger))
                                .foregroundStyle(Color(red: 0.173, green: 0.396, blue: 0.380))
                                .interpolationMethod(.linear)
                        }
                        if let appetite = day.appetite {
                            LineMark(x: .value("d", day.day), y: .value(L("Аппетит", "Appetite"), appetite))
                                .foregroundStyle(Color(red: 0.588, green: 0.282, blue: 0.165))
                                .interpolationMethod(.linear)
                        }
                    }
                }
                .chartYScale(domain: 1...5)
                .frame(height: 140)
                .accessibilityLabel(L("Голод и аппетит по дням", "Hunger and appetite by day"))
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var grid: some View {
        let cells = snapshot.food.hungerAppetitePairs
        let total = max(1, cells.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Голод и аппетит", "Hunger and appetite")).font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Spacer()
                Button(gridMode ? L("Доли", "Share") : L("Числа", "Counts")) { gridMode.toggle() }
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.forest)
            }
            Text(L("По горизонтали — аппетит (мало → много), по вертикали — голод (слабый сверху? нет: сильный сверху).", "Horizontal is appetite (low → high), vertical is hunger (strong at the top)."))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
            HStack {
                Text(L("сильный голод", "strong hunger")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
                Spacer()
                Text(L("много аппетита →", "more appetite →")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
            }
            ForEach([5, 4, 3, 2, 1], id: \.self) { hunger in
                HStack(spacing: 4) {
                    Text("\(hunger)")
                        .font(.lora(10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 14)
                    ForEach([1, 2, 3, 4, 5], id: \.self) { appetite in
                        let cell = cells.first { $0.hungerKey == "\(hunger)" && $0.appetiteKey == "\(appetite)" }
                        let count = cell?.count ?? 0
                        Button {
                            selectedCell = AnalyticsGridCell(hungerKey: "\(hunger)", appetiteKey: "\(appetite)", count: count)
                        } label: {
                            Text(gridMode ? "\(Int((Double(count) / Double(total) * 100).rounded()))%" : "\(count)")
                                .font(.lora(11, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(AppTheme.chipFill)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Голод \(hunger), аппетит \(appetite): \(count)", "Hunger \(hunger), appetite \(appetite): \(count)"))
                    }
                }
            }
            HStack {
                Text(L("слабый голод", "mild hunger")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
                Spacer()
            }
            if let selectedCell {
                Text(L("Голод \(selectedCell.hungerKey), аппетит \(selectedCell.appetiteKey): \(selectedCell.count) наблюдений", "Hunger \(selectedCell.hungerKey), appetite \(selectedCell.appetiteKey): \(selectedCell.count) observations"))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}
