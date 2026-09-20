import SwiftUI

/// Сравнение: two metrics on one time axis — sharing a scale only when they
/// are the same kind of number — and, on request, the days grouped by a
/// context ("sleep under 6 h", "period days") with the outcome's average in
/// each. Co-occurrence only; nothing here says one thing caused another.
struct CompareAnalyticsView: View {
    @Bindable var store: AnalyticsStore
    @AppStorage("analytics.compare.a") private var aRaw = AnalyticsMetric.mood.rawValue
    @AppStorage("analytics.compare.b") private var bRaw = AnalyticsMetric.energy.rawValue
    @State private var context = "sleepDuration"
    @State private var factorCategory: UUID?

    private var a: AnalyticsMetric { AnalyticsMetric(rawValue: aRaw) ?? .mood }
    private var b: AnalyticsMetric {
        let candidate = AnalyticsMetric(rawValue: bRaw) ?? .energy
        return candidate == a ? (a == .energy ? .mood : .energy) : candidate
    }

    var body: some View {
        let snapshot = store.snapshot
        let seriesA = AnalyticsChartSeries.make(metric: a, days: snapshot.days)
        let seriesB = AnalyticsChartSeries.make(metric: b, days: snapshot.days)
        let both = snapshot.days.filter { a.value(in: $0) != nil && b.value(in: $0) != nil }.count

        AnalyticsDetailScaffold(title: AnalyticsSection.compare.title, store: store) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AnalyticsMetricMenu(title: L("Первый показатель", "First metric"), selection: Binding(get: { a }, set: { aRaw = $0.rawValue }), excluding: b)
                    Text(L("и", "vs")).font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                    AnalyticsMetricMenu(title: L("Второй показатель", "Second metric"), selection: Binding(get: { b }, set: { bRaw = $0.rawValue }), excluding: a)
                }
                AnalyticsMetricChart(series: [seriesA, seriesB], interval: snapshot.interval, height: 200)
                if AnalyticsChartLayout.layout(for: [a, b]) == .stacked {
                    Text(L("Разные единицы — поэтому два графика на общей оси времени, а не одна шкала.", "Different units — so two charts on a shared time axis, not one scale."))
                        .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                }
                if both == 0 {
                    AnalyticsQuietNote(text: L("Нет дней, где записаны оба показателя.", "No days with both metrics recorded."))
                } else {
                    AnalyticsReliabilityBadge(
                        confidence: AnalyticsConfidence(independentCount: both),
                        extra: L("\(both) дн. с обоими показателями", "\(both) days with both")
                    )
                }
            }
            .padding(16)
            .parchmentCard(padding: 0)

            AnalyticsDisclosure(L("По условиям дней", "By day conditions")) { contextSection(snapshot) }
        }
    }

    // MARK: - Groups

    private var outcomeKey: String {
        switch a {
        case .energy: return "energy"
        case .motivation: return "motivation"
        case .appetite: return "appetite"
        case .satiety: return "hunger"
        case .sleep: return "sleep"
        case .rest: return "rest"
        case .work: return "work"
        case .study: return "study"
        default: return "mood"
        }
    }

    private var outcomeTitle: String {
        switch outcomeKey {
        case "hunger": return L("Голод (1–5)", "Hunger (1–5)")
        case "mood" where a != .mood: return AnalyticsMetric.mood.title
        default: return a.title
        }
    }

    private var contexts: [(key: String, title: String)] {
        var items: [(key: String, title: String)] = [
            ("sleepDuration", L("Длительность сна", "Sleep duration")),
            ("sleepQuality", L("Качество сна", "Sleep quality")),
            ("support", L("Препараты", "Medication")),
            ("period", L("Менструация", "Period")),
            ("cycle", L("Этап цикла", "Cycle stage")),
            ("emotion", L("Эмоции", "Emotions")),
            ("impulse", L("Импульсивность", "Impulsivity")),
            ("sessionType", L("Тип сессии", "Session type")),
            ("food", L("Питание", "Food"))
        ]
        if store.snapshot.factors.contains(where: { !$0.categoryName.isEmpty }) {
            items.append(("factor", L("Пользовательское условие", "Custom condition")))
        }
        return items
    }

    private func contextSection(_ snapshot: AnalyticsSnapshot) -> some View {
        let groups = AnalyticsEngine.compare(days: snapshot.days, outcome: outcomeKey, groups: groupSpecs(snapshot))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("Показатель: ", "Metric: ") + outcomeTitle).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                Spacer(minLength: 8)
                Menu {
                    ForEach(contexts, id: \.key) { item in
                        Button { context = item.key } label: {
                            if item.key == context { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(contexts.first { $0.key == context }?.title ?? "").font(.lora(13, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Capsule().fill(AppTheme.chipFill))
                    .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
                }
                .accessibilityLabel(L("Контекст", "Context"))
            }
            if context == "factor" { factorCategoryMenu(snapshot) }
            if groups.allSatisfy({ $0.dayCount == 0 }) {
                AnalyticsQuietNote(text: L("Нет дней с выбранным контекстом в этом периоде.", "No days with this context in the period."))
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(group.label).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 8)
                            Text(format(group.average)).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        }
                        Text(L("\(group.dayCount) дн. · \(group.observationCount) наблюдений", "\(group.dayCount) days · \(group.observationCount) observations"))
                            .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                        AnalyticsReliabilityBadge(confidence: group.confidence)
                    }
                }
                let usable = groups.filter { $0.confidence != .insufficient && $0.average != nil }
                if usable.count >= 2, let first = usable.first, let second = usable.dropFirst().first, let x = first.average, let y = second.average {
                    Text(L("В дни «\(first.label)» среднее было \(diff(x - y)) относительно «\(second.label)». Связь может зависеть от других факторов.",
                           "On “\(first.label)” days the average was \(diff(x - y)) versus “\(second.label)”. The link may depend on other factors."))
                        .font(.lora(12)).foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    private func factorCategoryMenu(_ snapshot: AnalyticsSnapshot) -> some View {
        let categories = Dictionary(grouping: snapshot.factors, by: \.categoryID)
        let ids = categories.keys.sorted { (categories[$0]?.first?.categoryName ?? "") < (categories[$1]?.first?.categoryName ?? "") }
        return Menu {
            ForEach(ids, id: \.self) { id in
                Button(Ldata(categories[id]?.first?.categoryName ?? "")) { factorCategory = id }
            }
        } label: {
            Text(Ldata(categories[factorCategory ?? ids.first ?? UUID()]?.first?.categoryName ?? L("категория", "category")))
                .font(.lora(13, weight: .medium)).foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Capsule().fill(AppTheme.chipFill))
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }
    }

    private func groupSpecs(_ snapshot: AnalyticsSnapshot) -> [(id: String, label: String, include: (AnalyticsDayRow) -> Bool)] {
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
                ("none", L("Дни без записей еды", "Days without food records"), { !$0.hasFood })
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
            return snapshot.factors.filter { $0.categoryID == category }.map { option in
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
        ["rest", "work", "study", "sleep"].contains(outcomeKey) ? analyticsDuration(value.map { $0 * 3600 }) : analyticsFormat(value)
    }

    private func diff(_ value: Double) -> String {
        if ["rest", "work", "study", "sleep"].contains(outcomeKey) {
            return (value >= 0 ? "+" : "−") + DurationFormatting.compact(abs(value) * 3600)
        }
        return String(format: "%+.1f", value)
    }
}
