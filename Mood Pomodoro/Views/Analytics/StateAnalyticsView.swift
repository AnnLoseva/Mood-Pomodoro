import SwiftUI

/// Состояние: mood, energy and motivation, plus — behind disclosures — the
/// reasons people gave and what tends to go along with a different mood.
struct StateAnalyticsView: View {
    @Bindable var store: AnalyticsStore

    private let metrics: [AnalyticsMetric] = [.mood, .energy, .motivation]

    var body: some View {
        let snapshot = store.snapshot
        let o = snapshot.overview
        AnalyticsDetailScaffold(title: AnalyticsSection.state.title, store: store) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    let average = average(of: metric, in: o)
                    NavigationLink(value: AnalyticsRoute.metric(metric)) {
                        HStack(spacing: 10) {
                            Image(systemName: metric.shape.symbolName(filled: true))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(metric.color)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.title)
                                    .font(.lora(15, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                                Text(average.dayCount == 0
                                     ? L("нет данных", "no data")
                                     : L("по \(average.dayCount) дн. · \(average.observationCount) отметок", "over \(average.dayCount) days · \(average.observationCount) check-ins"))
                                    .font(.lora(12))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                            Spacer(minLength: 8)
                            Text(analyticsFormat(average.average))
                                .font(.lora(16, weight: .semibold))
                                .foregroundStyle(metric.textColor)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < metrics.count - 1 { Divider().overlay(AppTheme.border) }
                }
            }
            .padding(.horizontal, 16)
            .parchmentCard(padding: 0)

            let reasons = Array(snapshot.reasons.prefix(10))
            AnalyticsDisclosure(L("Частые причины", "Common reasons"), summary: reasons.isEmpty ? "—" : "\(reasons.count)") {
                if reasons.isEmpty {
                    AnalyticsQuietNote(text: L("Пока мало заполненных причин.", "Too few filled-in reasons yet."))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(reasons) { row in
                            HStack {
                                Text(Ldata(row.reason)).font(.lora(14)).foregroundStyle(AppTheme.ink)
                                Spacer(minLength: 8)
                                Text("\(row.count) / \(row.answeredTotal)")
                                    .font(.lora(13, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                        Text(L("Считается по отметкам, где причина указана.", "Counted over check-ins where a reason was given."))
                            .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }

            let links = factorLinks(snapshot)
            AnalyticsDisclosure(L("Что связано с настроением", "What goes with mood"), summary: links.isEmpty ? "—" : "\(links.count)") {
                if links.isEmpty {
                    AnalyticsQuietNote(text: L("Пока не хватает дней для сравнений.", "Not enough days for comparisons yet."))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(links) { row in
                            NavigationLink(value: AnalyticsRoute.factorCategory(row.categoryID)) {
                                HStack {
                                    Text(Ldata(row.optionName)).font(.lora(14)).foregroundStyle(AppTheme.ink)
                                    Spacer(minLength: 8)
                                    Text(String(format: "%+.1f", row.moodDelta ?? 0))
                                        .font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                    Text("\(row.dayCount) " + L("дн.", "d"))
                                        .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Text(L("В дни с этим условием среднее настроение было другим. Это наблюдение, а не причина.", "On days with this condition average mood was different. An observation, not a cause."))
                            .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }

            if !o.deltas.isEmpty {
                AnalyticsDisclosure(L("К прошлому периоду", "Versus the previous period"), summary: "\(o.deltas.count)") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(o.deltas, id: \.key) { delta in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(delta.title).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                    Spacer(minLength: 8)
                                    Text(AnalyticsDeltaFormat.signed(delta))
                                        .font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                }
                                Text(L("\(delta.currentDays) дн. сейчас · \(delta.previousDays) дн. раньше · \(delta.confidence.shortLabel)",
                                       "\(delta.currentDays) days now · \(delta.previousDays) days before · \(delta.confidence.shortLabel)"))
                                    .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                AnalyticsRouteRow(title: AnalyticsSection.emotions.title, route: .section(.emotions))
                Divider().overlay(AppTheme.border)
                AnalyticsRouteRow(title: AnalyticsSection.factors.title, route: .section(.factors))
            }
            .padding(.horizontal, 16)
            .parchmentCard(padding: 0)
        }
    }

    private func average(of metric: AnalyticsMetric, in o: AnalyticsOverview) -> AnalyticsScaleAverage {
        switch metric {
        case .energy: return o.energy
        case .motivation: return o.motivation
        default: return o.mood
        }
    }

    /// The factors with a sample big enough to say anything, biggest
    /// difference first — both directions in one list, told apart by sign.
    private func factorLinks(_ snapshot: AnalyticsSnapshot) -> [AnalyticsFactorRow] {
        snapshot.factors
            .filter { $0.confidence != .insufficient && ($0.moodDelta ?? 0) != 0 }
            .sorted { abs($0.moodDelta ?? 0) > abs($1.moodDelta ?? 0) }
            .prefix(8)
            .map { $0 }
    }
}
