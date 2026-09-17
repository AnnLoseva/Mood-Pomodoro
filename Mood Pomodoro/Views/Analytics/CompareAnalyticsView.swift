import SwiftUI

struct CompareAnalyticsView: View {
    let snapshot: AnalyticsSnapshot
    @State private var outcome = "mood"
    @State private var context = "sleepDuration"
    @State private var factorCategory: UUID?

    private let outcomes: [(key: String, title: String)] = [
        ("mood", L("Настроение", "Mood")),
        ("energy", L("Энергия", "Energy")),
        ("motivation", L("Мотивация", "Motivation")),
        ("appetite", L("Аппетит", "Appetite")),
        ("hunger", L("Голод", "Hunger")),
        ("rest", L("Длительность отдыха", "Rest duration")),
        ("work", L("Длительность работы", "Work duration")),
        ("study", L("Длительность учёбы", "Study duration"))
    ]

    private var contexts: [(key: String, title: String)] {
        var items: [(key: String, title: String)] = [
            ("sleepDuration", L("Длительность сна", "Sleep duration")),
            ("sleepQuality", L("Качество сна", "Sleep quality")),
            ("support", L("Препараты", "Medication")),
            ("period", L("Менструация", "Period")),
            ("cycle", L("Этап цикла", "Cycle stage")),
            ("emotion", L("Эмоции", "Emotions")),
            ("impulse", L("Импульсивность", "Impulsivity")),
            ("sessionType", L("Тип сеанса", "Session type")),
            ("food", L("Питание", "Food"))
        ]
        if snapshot.factors.contains(where: { !$0.categoryName.isEmpty }) {
            items.append(("factor", L("Пользовательское состояние", "Custom condition")))
        }
        return items
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                picker(L("Результат", "Outcome"), options: outcomes, selection: $outcome)
                picker(L("Контекст", "Context"), options: contexts, selection: $context)
                if context == "factor" {
                    factorCategoryPicker
                }

                let groups = AnalyticsEngine.compare(days: snapshot.days, outcome: outcome, groups: groupSpecs)
                if groups.allSatisfy({ $0.dayCount == 0 }) {
                    AnalyticsEmptyCard(
                        title: L("Недостаточно записей для сравнения", "Not enough records to compare"),
                        message: L("Нужны дни с выбранным результатом и контекстом в этом периоде.", "Need days that have both the chosen outcome and context in this period.")
                    )
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.label).font(.lora(15, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            Text(L(
                                "\(group.dayCount) дн. · \(group.observationCount) наблюдений · среднее \(format(group.average))",
                                "\(group.dayCount) days · \(group.observationCount) observations · average \(format(group.average))"
                            ))
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                            AnalyticsReliabilityBadge(confidence: group.confidence)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .parchmentCard(padding: 0)
                    }
                    let usable = groups.filter { $0.confidence != .insufficient && $0.average != nil }
                    if usable.count >= 2, let first = usable.first, let second = usable.dropFirst().first, let a = first.average, let b = second.average {
                        Text(L(
                            "В дни с «\(first.label)» среднее было \(String(format: "%+.1f", a - b)) относительно «\(second.label)». Связь может зависеть от других факторов.",
                            "On days with “\(first.label)” the average was \(String(format: "%+.1f", a - b)) versus “\(second.label)”. The link may depend on other factors."
                        ))
                        .font(.lora(13))
                        .foregroundStyle(AppTheme.ink)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private var factorCategoryPicker: some View {
        let categories = Dictionary(grouping: snapshot.factors, by: \.categoryID)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories.keys.sorted { a, b in
                    (categories[a]?.first?.categoryName ?? "") < (categories[b]?.first?.categoryName ?? "")
                }, id: \.self) { id in
                    let on = factorCategory == id
                    Button { factorCategory = id } label: {
                        Text(Ldata(categories[id]?.first?.categoryName ?? ""))
                            .font(.lora(12, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? AppTheme.parchmentCard : AppTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(on ? AppTheme.forest : AppTheme.chipFill))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .parchmentCard()
    }

    private var groupSpecs: [(id: String, label: String, include: (AnalyticsDayRow) -> Bool)] {
        switch context {
        case "sleepDuration":
            return [
                ("short", L("Сон < 6 ч", "Sleep < 6h"), { ($0.sleepSeconds ?? 0) > 0 && ($0.sleepSeconds ?? 0) < 6 * 3600 }),
                ("mid", L("Сон 6–8 ч", "Sleep 6–8h"), { let s = $0.sleepSeconds ?? 0; return s >= 6 * 3600 && s < 8 * 3600 }),
                ("long", L("Сон > 8 ч", "Sleep > 8h"), { ($0.sleepSeconds ?? 0) >= 8 * 3600 })
            ]
        case "support":
            return [
                ("taken", L("Принято", "Taken"), { $0.supportRaw == SupportStatus.taken.rawValue }),
                ("skipped", L("Не принято", "Not taken"), { $0.supportRaw == SupportStatus.notTaken.rawValue }),
                ("unrecorded", L("Не отмечено", "Not recorded"), { $0.supportRaw == nil })
            ]
        case "period":
            return [
                ("period", L("Дни менструации", "Period days"), { $0.isPeriodDay }),
                ("other", L("Остальные дни", "Other days"), { !$0.isPeriodDay })
            ]
        case "cycle":
            return [
                ("d1", L("Дни 1–5", "Days 1–5"), { ($0.cycleDay ?? 0) >= 1 && ($0.cycleDay ?? 0) <= 5 }),
                ("d2", L("Дни 6–14", "Days 6–14"), { ($0.cycleDay ?? 0) >= 6 && ($0.cycleDay ?? 0) <= 14 }),
                ("d3", L("Дни 15–28", "Days 15–28"), { ($0.cycleDay ?? 0) >= 15 && ($0.cycleDay ?? 0) <= 28 }),
                ("d4", L("День 29+", "Day 29+"), { ($0.cycleDay ?? 0) >= 29 }),
                ("unknown", L("Цикл не отмечен", "Cycle not marked"), { $0.cycleDay == nil })
            ]
        case "food":
            return [
                ("food", L("Дни с едой", "Days with food"), { $0.hasFood }),
                ("none", L("Дни без еды", "Days without food"), { !$0.hasFood })
            ]
        case "impulse":
            return [
                ("marked", L("Дни с отметкой импульса", "Days with an impulse mark"), { $0.impulseCount > 0 }),
                ("unmarked", L("Дни без таких отметок", "Days without those marks"), { $0.impulseCount == 0 })
            ]
        case "sessionType":
            return [
                ("rest", L("Отдых", "Rest"), { ($0.durationByType[SessionType.rest.rawValue] ?? 0) > 0 }),
                ("work", L("Обязательная работа", "Obligatory work"), { ($0.durationByType[SessionType.obligatoryWork.rawValue] ?? 0) > 0 }),
                ("study", L("Учёба", "Study"), { ($0.durationByType[SessionType.study.rawValue] ?? 0) > 0 }),
                ("untyped", SessionType.unassignedLabel, { ($0.durationByType["unassigned"] ?? 0) > 0 })
            ]
        case "emotion":
            return Emotion.allCases.map { emotion in
                (emotion.rawValue, emotion.label, { $0.emotions.contains(emotion.rawValue) })
            }
        case "factor":
            let category = factorCategory ?? snapshot.factors.first?.categoryID
            let options = snapshot.factors.filter { $0.categoryID == category }
            return options.map { option in
                (option.id, Ldata(option.optionName), { $0.factorKeys.contains(option.id) })
            }
        default:
            return [
                ("lowQ", L("Качество сна ≤ 2", "Sleep quality ≤ 2"), { ($0.sleepQuality ?? 3) <= 2 }),
                ("highQ", L("Качество сна ≥ 4", "Sleep quality ≥ 4"), { ($0.sleepQuality ?? 3) >= 4 })
            ]
        }
    }

    private func format(_ value: Double?) -> String {
        let durationKeys: Set<String> = ["rest", "work", "study"]
        if durationKeys.contains(outcome) {
            return analyticsDuration(value.map { $0 * 3600 })
        }
        return analyticsFormat(value)
    }

    private func picker(_ title: String, options: [(key: String, title: String)], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.lora(13, weight: .medium)).foregroundStyle(AppTheme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.key) { item in
                        let on = selection.wrappedValue == item.key
                        Button { selection.wrappedValue = item.key } label: {
                            Text(item.title)
                                .font(.lora(12, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? AppTheme.parchmentCard : AppTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(on ? AppTheme.forest : AppTheme.chipFill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .parchmentCard()
    }
}
