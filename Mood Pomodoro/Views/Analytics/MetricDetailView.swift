import SwiftUI

/// One metric in depth: the chart, the few figures that describe it, and —
/// on request — the day-by-day values, each leading to that day's records.
struct MetricDetailView: View {
    let metric: AnalyticsMetric
    @Bindable var store: AnalyticsStore

    var body: some View {
        let snapshot = store.snapshot
        let series = AnalyticsChartSeries.make(metric: metric, days: snapshot.days)
        AnalyticsDetailScaffold(title: metric.title, store: store) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    AnalyticsMetricPill(metric: metric)
                    Text(metric.unitNote).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                    Spacer(minLength: 0)
                    AnalyticsInfoButton(text: metric.methodNote + "\n\n" + L("Дни без записи остаются пропусками.", "Days without a record stay gaps."))
                }
                AnalyticsMetricChart(series: [series], interval: snapshot.interval, height: 220)
                figures(series, snapshot: snapshot)
            }
            .padding(16)
            .parchmentCard(padding: 0)

            if let delta = snapshot.overview.deltas.first(where: { $0.key == metric.rawValue }) {
                previousPeriod(delta)
            }

            related

            if !series.isEmpty {
                AnalyticsDisclosure(L("По дням", "Day by day"), summary: "\(series.points.count)") {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(series.points.reversed()) { point in
                            NavigationLink(value: AnalyticsRoute.day(point.day)) {
                                HStack {
                                    Text(DateFormatting.fullDate(point.day))
                                        .font(.lora(14))
                                        .foregroundStyle(AppTheme.ink)
                                    Spacer(minLength: 8)
                                    Text(metric.formatWithUnit(point.value))
                                        .font(.lora(14, weight: .semibold))
                                        .foregroundStyle(metric.textColor)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Figures

    private func figures(_ series: AnalyticsChartSeries, snapshot: AnalyticsSnapshot) -> some View {
        let values = series.points.map(\.value)
        let dayCount = snapshot.overview.dayCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                AnalyticsStatTile(title: L("Среднее", "Average"), value: metric.formatWithUnit(series.average))
                AnalyticsStatTile(
                    title: L("Дней с данными", "Days with data"),
                    value: dayCount > 0 ? "\(series.points.count) / \(dayCount)" : "\(series.points.count)"
                )
            }
            if let low = values.min(), let high = values.max(), series.points.count > 1 {
                HStack {
                    AnalyticsStatTile(title: L("Меньше всего", "Lowest"), value: metric.formatWithUnit(low))
                    AnalyticsStatTile(title: L("Больше всего", "Highest"), value: metric.formatWithUnit(high))
                }
            }
            AnalyticsReliabilityBadge(
                confidence: AnalyticsConfidence(independentCount: series.points.count),
                extra: L("единица: день", "unit: day")
            )
        }
    }

    private func previousPeriod(_ delta: AnalyticsDelta) -> some View {
        AnalyticsDisclosure(L("К прошлому периоду", "Versus the previous period"), summary: signed(delta)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L(
                    "сейчас \(format(delta.current, key: delta.key)) · \(delta.currentDays) дн.",
                    "now \(format(delta.current, key: delta.key)) · \(delta.currentDays) days"
                ))
                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                Text(L(
                    "раньше \(format(delta.previous, key: delta.key)) · \(delta.previousDays) дн.",
                    "before \(format(delta.previous, key: delta.key)) · \(delta.previousDays) days"
                ))
                .font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                AnalyticsReliabilityBadge(confidence: delta.confidence)
            }
        }
    }

    private func signed(_ delta: AnalyticsDelta) -> String {
        AnalyticsDeltaFormat.signed(delta)
    }

    private func format(_ value: Double, key: String) -> String {
        AnalyticsDeltaFormat.value(value, key: key)
    }

    // MARK: - Ways on

    private var related: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch metric {
            case .sleep:
                AnalyticsRouteRow(title: L("Ночи", "Nights"), route: .nights)
                Divider().overlay(AppTheme.border)
                AnalyticsRouteRow(title: L("Всё о сне", "Everything about sleep"), route: .section(.sleep))
            case .activity, .rest, .work, .study:
                AnalyticsRouteRow(title: L("Все сессии", "All sessions"), route: .sessions(activity: nil))
                Divider().overlay(AppTheme.border)
                AnalyticsRouteRow(title: L("Занятия по названиям", "Activities by name"), route: .section(.activities))
            case .satiety, .appetite:
                AnalyticsRouteRow(title: L("Всё о питании", "Everything about food"), route: .section(.food))
            case .mood, .energy, .motivation:
                AnalyticsRouteRow(title: L("Всё о состоянии", "Everything about state"), route: .section(.state))
            }
            Divider().overlay(AppTheme.border)
            AnalyticsRouteRow(title: L("Сравнить с другим показателем", "Compare with another metric"), route: .section(.compare))
        }
        .padding(.horizontal, 16)
        .parchmentCard(padding: 0)
    }
}

enum AnalyticsDeltaFormat {
    /// A change between two periods in the unit of its own metric — sleep in
    /// hours and minutes, ratings in points.
    static func signed(_ delta: AnalyticsDelta) -> String {
        if delta.key == "sleep" {
            let sign = delta.difference >= 0 ? "+" : "−"
            return sign + DurationFormatting.compact(abs(delta.difference))
        }
        return String(format: "%+.1f", delta.difference)
    }

    static func value(_ value: Double, key: String) -> String {
        key == "sleep" ? DurationFormatting.compact(value) : analyticsFormat(value)
    }
}

/// A row that pushes an analytics route.
struct AnalyticsRouteRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    let route: AnalyticsRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.lora(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
