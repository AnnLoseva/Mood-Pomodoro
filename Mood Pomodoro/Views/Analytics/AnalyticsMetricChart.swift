import SwiftUI
import Charts

/// The analytics chart: one or two metrics over the chosen period, each on
/// a scale of its own kind.
///
/// - Ratings (1–5) share one axis with each other; hours share one with
///   hours. A rating and a duration are never put on one axis: they are
///   drawn as two stacked panels on the same time axis.
/// - A day with no record is a gap. Lines run only through consecutive
///   days, single days are dots, durations are bars — nothing is drawn
///   across a day that has no value.
/// - Tapping a day opens a card with the actual value, its unit and how it
///   was formed, and the way to the records behind it.
struct AnalyticsMetricChart: View {
    let series: [AnalyticsChartSeries]
    let interval: DateInterval
    var height: CGFloat = 200

    @State private var selectedDay: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsOpen) private var open
    @Environment(AppTabs.self) private var tabs

    private var layout: AnalyticsChartLayout { AnalyticsChartLayout.layout(for: series.map(\.metric)) }
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if series.count > 1 { legend }

            if series.allSatisfy(\.isEmpty) {
                AnalyticsQuietNote(text: L("Нет записей за этот период.", "No records in this period."))
            } else if layout == .shared {
                plot(series, height: height)
            } else {
                ForEach(series) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.metric.title) · \(item.metric.unitNote)")
                            .font(.lora(11))
                            .foregroundStyle(item.metric.textColor)
                        plot([item], height: max(110, height * 0.6))
                    }
                }
            }

            if let day = selectedDay {
                selectionCard(for: day)
            }
        }
        .onChange(of: series.map(\.id)) { _, _ in selectedDay = nil }
        .onChange(of: interval) { _, _ in selectedDay = nil }
    }

    // MARK: - Plot

    private func plot(_ list: [AnalyticsChartSeries], height: CGFloat) -> some View {
        let metrics = list.map(\.metric)
        let domain = AnalyticsMetric.domain(for: metrics, values: list.flatMap { $0.points.map(\.value) })
        let count = list.map { $0.points.count }.max() ?? 0
        let usesBars = list.count == 1 && list[0].metric.unit == .hours
        let symbolSize: CGFloat = count <= 31 ? 70 : (count <= 90 ? 40 : 22)

        return Chart {
            ForEach(list) { item in
                if usesBars {
                    ForEach(item.points) { point in
                        BarMark(
                            x: .value(L("День", "Day"), point.day, unit: .day),
                            y: .value(item.metric.title, point.value)
                        )
                        .foregroundStyle(item.metric.color)
                        .cornerRadius(2)
                    }
                } else {
                    ForEach(Array(item.runs.enumerated()), id: \.offset) { index, run in
                        if run.count > 1 {
                            ForEach(run) { point in
                                LineMark(
                                    x: .value(L("День", "Day"), point.day, unit: .day),
                                    y: .value(item.metric.title, point.value),
                                    series: .value("run", "\(item.id)-\(index)")
                                )
                                .foregroundStyle(item.metric.color)
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            }
                        }
                    }
                    ForEach(item.runs.flatMap { $0 }) { point in
                        // Long histories drop the dots and keep the line —
                        // except lone days, which have nothing else to show.
                        let isolated = item.runs.contains { $0.count == 1 && $0[0].day == point.day }
                        if count <= 120 || isolated {
                            PointMark(
                                x: .value(L("День", "Day"), point.day, unit: .day),
                                y: .value(item.metric.title, point.value)
                            )
                            .foregroundStyle(item.metric.color)
                            .symbol(item.metric.shape.chartSymbol)
                            .symbolSize(symbolSize)
                        }
                    }
                }
            }
            if let day = selectedDay {
                RuleMark(x: .value(L("День", "Day"), day, unit: .day))
                    .foregroundStyle(AppTheme.ink.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: domain)
        .chartYAxis {
            if list.allSatisfy({ $0.metric.unit == .rating }) {
                AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)").font(.lora(10)).foregroundStyle(AppTheme.inkSoft) }
                    }
                }
            } else {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(L("\(Int(v)) ч", "\(Int(v)) h")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xTicks) { _ in
                AxisGridLine().foregroundStyle(AppTheme.border.opacity(0.6))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale))
                    .font(.lora(10))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        // A plain tap selects the day. (`chartXSelection` ends its selection the
        // moment the finger lifts, so a quick tap never reached the card.)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geo[frame].origin.x
                        guard let tapped: Date = proxy.value(atX: x) else { return }
                        let day = calendar.startOfDay(for: tapped)
                        guard day >= interval.start, day < interval.end else { return }
                        selectedDay = day
                    }
                    .accessibilityHidden(true)
            }
        }
        .environment(\.locale, AppLanguage.current.locale)
        .frame(height: height)
        .accessibilityLabel(accessibilitySummary(list))
    }

    /// A few evenly spaced day starts, none at the very end of the window —
    /// where a label would run off the card.
    private var xTicks: [Date] {
        let days = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
        let count = min(4, days)
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: index * days / count, to: interval.start)
        }
    }

    private func accessibilitySummary(_ list: [AnalyticsChartSeries]) -> String {
        list.map { item in
            let average = item.metric.formatWithUnit(item.average)
            return L(
                "\(item.metric.title): \(item.points.count) дн. с данными, среднее \(average)",
                "\(item.metric.title): \(item.points.count) days with data, average \(average)"
            )
        }.joined(separator: ". ")
    }

    // MARK: - Legend

    private var legend: some View {
        FlowLayout(spacing: 12) {
            ForEach(series) { item in
                HStack(spacing: 5) {
                    Image(systemName: item.metric.shape.symbolName(filled: true))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.metric.color)
                    Text(item.metric.title)
                        .font(.lora(12, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    // MARK: - Selected day

    private func selectionCard(for day: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DateFormatting.fullDate(day))
                    .font(.lora(13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button {
                    selectedDay = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Закрыть", "Close"))
            }
            ForEach(series) { item in
                let point = item.point(on: day)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: item.metric.shape.symbolName(filled: true))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.metric.color)
                    Text(item.metric.title)
                        .font(.lora(13))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 8)
                    if let point {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.metric.formatWithUnit(point.value))
                                .font(.lora(14, weight: .semibold))
                                .foregroundStyle(item.metric.textColor)
                            Text(provenance(item.metric, point))
                                .font(.lora(11))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    } else {
                        Text(L("нет данных", "no data"))
                            .font(.lora(13))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 8) {
                Button(L("Записи дня", "Day's records")) { open(.day(day)) }
                    .buttonStyle(AnalyticsSmallButtonStyle())
                Button(L("В дневнике", "In the diary")) { tabs.openDiary(day: day) }
                    .buttonStyle(AnalyticsSmallButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.chipFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
        .transition(reduceMotion ? .identity : .opacity)
    }

    /// What the day's number is made of — an aggregate says so.
    private func provenance(_ metric: AnalyticsMetric, _ point: AnalyticsChartSeries.Point) -> String {
        switch metric.unit {
        case .rating:
            let n = point.observations ?? 0
            return L("среднее за день · \(countLabel(n, ru: ("отметка", "отметки", "отметок"), en: ("check-in", "check-ins")))",
                     "daily mean · \(countLabel(n, ru: ("отметка", "отметки", "отметок"), en: ("record", "records")))")
        case .hours:
            if metric == .sleep { return L("за ночь", "for the night") }
            let n = point.observations ?? 0
            return L("за день · \(countLabel(n, ru: ("сессия", "сессии", "сессий"), en: ("session", "sessions")))",
                     "for the day · \(countLabel(n, ru: ("сессия", "сессии", "сессий"), en: ("session", "sessions")))")
        }
    }
}

/// A compact metric picker: a coloured glyph and the name, opening a menu of
/// every metric. `excluding` hides the one already on the chart when this
/// picks the second series.
struct AnalyticsMetricMenu: View {
    let title: String?
    @Binding var selection: AnalyticsMetric
    var excluding: AnalyticsMetric?

    var body: some View {
        Menu {
            Section(L("Основные", "Main")) {
                ForEach(AnalyticsMetric.primary.filter { $0 != excluding }) { metric in item(metric) }
            }
            Section(L("Ещё", "More")) {
                ForEach(AnalyticsMetric.secondary.filter { $0 != excluding }) { metric in item(metric) }
            }
        } label: { AnalyticsMetricPill(metric: selection, showsChevron: true) }
        .accessibilityLabel(title ?? L("Показатель", "Metric"))
        .accessibilityValue(selection.title)
    }

    private func item(_ metric: AnalyticsMetric) -> some View {
        Button { selection = metric } label: {
            if metric == selection { Label(metric.title, systemImage: "checkmark") } else { Text(metric.title) }
        }
    }
}

struct AnalyticsMetricPill: View {
    let metric: AnalyticsMetric
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: metric.shape.symbolName(filled: true))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(metric.color)
            Text(metric.title)
                .font(.lora(14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Capsule().fill(metric.color.opacity(0.14)))
        .overlay(Capsule().stroke(metric.color.opacity(0.65), lineWidth: 1.25))
    }
}
