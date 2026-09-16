//
//  DayMetricsChart.swift
//  Mood Pomodoro
//

import SwiftUI
import UIKit
import Charts

/// The day's three scales on one clock: mood, energy and motivation, each
/// switchable so they can be read together or one at a time. Sessions are
/// drawn behind as tinted bands, so a dip can be seen against what was
/// being done at the time.
///
/// All three share the 1–5 axis because they are the same five-step shape —
/// the numbers are positions, never scores, and are only labelled as such
/// when more than one series is on and no single set of illustrations would
/// be honest for all of them.
struct DayMetricsChart: View {
    let summary: DailySummary

    /// Which series are on. Remembered across days and launches — going
    /// through the diary is usually looking for one thing at a time.
    @AppStorage("diary.day.chart.mood") private var showMood = true
    @AppStorage("diary.day.chart.energy") private var showEnergy = true
    @AppStorage("diary.day.chart.motivation") private var showMotivation = true

    /// Nil means the whole day is in view; otherwise the width of the
    /// visible window in seconds.
    @State private var visibleSpan: TimeInterval?
    @State private var scrollStart: Date?
    /// The span the current pinch started from, so a gesture scales from
    /// where it began rather than compounding every frame.
    @State private var spanAtPinchStart: TimeInterval?

    private static let minimumSpan: TimeInterval = 15 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricToggles
            if enabledMetrics.isEmpty {
                Text(L("Включи хотя бы один показатель.", "Turn on at least one of them."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                chart
                zoomControls
            }
        }
    }

    // MARK: - Series selection

    private func isOn(_ metric: DayMetric) -> Bool {
        switch metric {
        case .mood: return showMood
        case .energy: return showEnergy
        case .motivation: return showMotivation
        }
    }

    private func toggle(_ metric: DayMetric) {
        switch metric {
        case .mood: showMood.toggle()
        case .energy: showEnergy.toggle()
        case .motivation: showMotivation.toggle()
        }
    }

    /// On *and* recorded today — a switched-on series with nothing behind it
    /// would draw an empty line and stretch the legend for no reason.
    private var enabledMetrics: [DayMetric] {
        summary.recordedMetrics.filter(isOn)
    }

    /// When exactly one is shown, its own illustrations can label the axis.
    private var soleMetric: DayMetric? {
        enabledMetrics.count == 1 ? enabledMetrics.first : nil
    }

    private var metricToggles: some View {
        // Wraps rather than scrolls: three chips are just too wide for a
        // phone, and a row that scrolls looks like a chip cut in half.
        FlowLayout(spacing: 8) {
            ForEach(DayMetric.allCases) { metric in
                    let available = !summary.points(for: metric).isEmpty
                    let on = available && isOn(metric)
                    Button { toggle(metric) } label: {
                        HStack(spacing: 6) {
                            if let name = chipImageName(for: metric) {
                                Image(name)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .opacity(on ? 1 : 0.45)
                            }
                            Text(metric.title)
                                .font(.lora(12, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? metric.color : AppTheme.inkSoft)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(on ? metric.color.opacity(0.16) : AppTheme.parchment.opacity(0.4))
                        )
                        .overlay(
                            Capsule().stroke(on ? metric.color : AppTheme.border, lineWidth: on ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .opacity(available ? 1 : 0.45)
                    .accessibilityLabel(metric.title)
                    .accessibilityValue(available
                                        ? (on ? L("показан", "shown") : L("скрыт", "hidden"))
                                        : L("нет записей за день", "nothing recorded today"))
            }
        }
    }

    /// The step closest to the day's average, so the chip shows what the
    /// day actually looked like; the middle step stands in when there is
    /// nothing to average.
    private func chipImageName(for metric: DayMetric) -> String? {
        guard let average = summary.average(for: metric) else { return metric.imageName(forScale: 3) }
        return metric.imageName(forScale: Int(average.rounded()))
    }

    // MARK: - Chart

    private var hasActivities: Bool { !summary.activitySpans.isEmpty }

    /// One series as its own ChartContent so the type checker can finish.
    /// Symbols live on the LineMark — PointMark has no `series`, and a
    /// separate point family used to pull the extra lines onto one path.
    @ChartContentBuilder
    private func seriesMarks(for metric: DayMetric) -> some ChartContent {
        ForEach(summary.points(for: metric)) { point in
            if let value = point.scale(for: metric) {
                LineMark(
                    x: .value("Время", point.timestamp),
                    y: .value("Уровень", value),
                    series: .value("Показатель", metric.rawValue)
                )
                .foregroundStyle(metric.color)
                .interpolationMethod(.monotone)
                .symbol(point.origin == .manual ? BasicChartSymbolShape.diamond : .circle)
                .symbolSize(point.origin == .manual ? 50 : 36)
            }
        }
    }

    private var chart: some View {
        Chart {
            // Activities first, so the lines are drawn over them.
            ForEach(summary.activitySpans) { span in
                ForEach(span.workIntervals, id: \.self) { interval in
                    RectangleMark(
                        xStart: .value("Начало", interval.start),
                        xEnd: .value("Конец", interval.end),
                        yStart: .value("Уровень", 1.0),
                        yEnd: .value("Уровень", 5.0)
                    )
                    .foregroundStyle(activityColor(for: span).opacity(0.22))
                }
                // Marks where it began — and keeps a few-minute session,
                // too narrow for its band to show, visible at all.
                RuleMark(
                    x: .value("Начало", span.start),
                    yStart: .value("Уровень", 1.0),
                    yEnd: .value("Уровень", 5.0)
                )
                .foregroundStyle(activityColor(for: span).opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(enabledMetrics) { metric in
                seriesMarks(for: metric)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: domain)
        // The space above 5 holds the activity labels.
        .chartYScale(domain: 1...(hasActivities ? 6 : 5))
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: scrollBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if hasActivities, let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    ForEach(placedActivityLabels(proxy: proxy, plot: plot)) { label in
                        HStack(spacing: Self.labelDotSpacing) {
                            Circle()
                                .fill(label.color)
                                .frame(width: Self.labelDotSize, height: Self.labelDotSize)
                            Text(label.name)
                                .font(.custom(Self.labelFontName, fixedSize: Self.labelFontSize))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(width: label.width, height: Self.labelLaneHeight, alignment: .leading)
                        .offset(x: label.x, y: plot.minY + CGFloat(label.lane) * Self.labelLaneHeight)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let raw = value.as(Int.self) {
                    AxisValueLabel {
                        if let soleMetric, let emoji = soleMetric.emoji(forScale: raw) {
                            Text(emoji)
                        } else {
                            // Several scales at once: a position on the
                            // shared axis, labelled as nothing more.
                            Text("\(raw)")
                                .font(.lora(10))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(DateFormatting.time(date))
                            .font(.lora(10))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
        }
        .frame(height: hasActivities ? 200 : 170)
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = spanAtPinchStart ?? visibleLength
                    if spanAtPinchStart == nil { spanAtPinchStart = base }
                    setSpan(base / value.magnification)
                }
                .onEnded { _ in spanAtPinchStart = nil }
        )
    }

    // MARK: - Zoom and pan

    private var domain: ClosedRange<Date> {
        var dates = summary.moodPoints.map(\.timestamp)
        dates += summary.activitySpans.flatMap { [$0.start, $0.end] }
        let dayStart = summary.date
        guard let first = dates.min(), let last = dates.max() else {
            return dayStart...dayStart.addingTimeInterval(24 * 3600)
        }
        let pad = max(5 * 60, last.timeIntervalSince(first) * 0.04)
        var start = first.addingTimeInterval(-pad)
        var end = last.addingTimeInterval(pad)
        // A day holding one check-in would otherwise have no width at all.
        if end.timeIntervalSince(start) < Self.minimumSpan * 2 {
            let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            start = middle.addingTimeInterval(-Self.minimumSpan)
            end = middle.addingTimeInterval(Self.minimumSpan)
        }
        return start...end
    }

    private var fullSpan: TimeInterval {
        domain.upperBound.timeIntervalSince(domain.lowerBound)
    }

    private var visibleLength: TimeInterval {
        min(visibleSpan ?? fullSpan, fullSpan)
    }

    private var isZoomed: Bool { visibleLength < fullSpan - 1 }

    private var canZoom: Bool { fullSpan > Self.minimumSpan * 1.5 }

    private var scrollBinding: Binding<Date> {
        Binding(
            get: { scrollStart ?? domain.lowerBound },
            set: { scrollStart = $0 }
        )
    }

    /// Re-centres on what was in the middle of the window, so zooming keeps
    /// looking at the same part of the day instead of jumping to its start.
    private func setSpan(_ raw: TimeInterval) {
        let full = fullSpan
        let clamped = min(max(raw, Self.minimumSpan), full)
        let centre = (scrollStart ?? domain.lowerBound).addingTimeInterval(visibleLength / 2)
        guard clamped < full - 1 else {
            visibleSpan = nil
            scrollStart = domain.lowerBound
            return
        }
        visibleSpan = clamped
        let half = clamped / 2
        let lowest = domain.lowerBound.addingTimeInterval(half)
        let highest = max(lowest, domain.upperBound.addingTimeInterval(-half))
        scrollStart = min(max(centre, lowest), highest).addingTimeInterval(-half)
    }

    @ViewBuilder
    private var zoomControls: some View {
        if canZoom {
            HStack(spacing: 8) {
                zoomButton(systemName: "minus.magnifyingglass", label: L("Отдалить", "Zoom out")) {
                    setSpan(visibleLength * 1.8)
                }
                .disabled(!isZoomed)
                zoomButton(systemName: "plus.magnifyingglass", label: L("Приблизить", "Zoom in")) {
                    setSpan(visibleLength / 1.8)
                }
                .disabled(visibleLength <= Self.minimumSpan + 1)
                Spacer(minLength: 4)
                if isZoomed {
                    Button(L("Весь день", "Whole day")) {
                        visibleSpan = nil
                        scrollStart = domain.lowerBound
                    }
                    .font(.lora(12, weight: .medium))
                    .foregroundStyle(AppTheme.forest)
                } else {
                    Text(L("Сведи пальцы, чтобы приблизить", "Pinch to zoom in"))
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
    }

    private func zoomButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.forest)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(AppTheme.parchment.opacity(0.5)))
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Activity labels

    private struct PlacedActivityLabel: Identifiable {
        let id: UUID
        let name: String
        let color: Color
        let x: CGFloat
        let lane: Int
        let width: CGFloat
    }

    /// Muted woodland tones that stay distinct from the three series lines.
    private static let activityPalette: [Color] = [
        AppTheme.moss,
        Color(red: 0.769, green: 0.584, blue: 0.259),
        Color(red: 0.357, green: 0.463, blue: 0.541),
        Color(red: 0.522, green: 0.365, blue: 0.447),
        AppTheme.rust
    ]

    private static let labelFontName = "Lora-Medium"
    private static let labelFontSize: CGFloat = 10
    private static let labelDotSize: CGFloat = 6
    private static let labelDotSpacing: CGFloat = 3
    private static let labelLaneHeight: CGFloat = 14
    private static let labelLaneCount = 2
    private static let labelGap: CGFloat = 6
    private static let labelFont = UIFont(name: labelFontName, size: labelFontSize)
        ?? .systemFont(ofSize: labelFontSize, weight: .medium)

    /// The same activity keeps one color through the day.
    private func activityColor(for span: ActivitySpan) -> Color {
        var names: [String] = []
        for other in summary.activitySpans where !names.contains(other.activityName) {
            names.append(other.activityName)
        }
        let index = names.firstIndex(of: span.activityName) ?? 0
        return Self.activityPalette[index % Self.activityPalette.count]
    }

    /// Each label starts where its activity starts and sits in the first of
    /// two lanes above the chart with room for it. A short session is often
    /// narrower than its name, so labels may run past their band — but never
    /// over another label; one that can't fit anywhere is shifted right and
    /// truncated, or left out if there is no room at all. Sessions scrolled
    /// off the side are skipped rather than piled against the edge.
    private func placedActivityLabels(proxy: ChartProxy, plot: CGRect) -> [PlacedActivityLabel] {
        var laneEnds = Array(repeating: -CGFloat.infinity, count: Self.labelLaneCount)
        return summary.activitySpans.compactMap { span in
            guard let startX = proxy.position(forX: span.start) else { return nil }
            let endX = proxy.position(forX: span.end) ?? startX
            guard endX >= 0, startX <= plot.width else { return nil }
            let name = span.activityName.isEmpty ? L("Сессия", "Session") : Ldata(span.activityName)
            let textWidth = (name as NSString).size(withAttributes: [.font: Self.labelFont]).width
            let naturalWidth = ceil(textWidth) + Self.labelDotSize + Self.labelDotSpacing + 2
            let preferredX = max(plot.minX, min(plot.minX + startX, plot.maxX - naturalWidth))

            let lane: Int
            var x = preferredX
            if let free = laneEnds.firstIndex(where: { $0 + Self.labelGap <= preferredX }) {
                lane = free
            } else {
                lane = laneEnds.indices.min { laneEnds[$0] < laneEnds[$1] } ?? 0
                x = laneEnds[lane] + Self.labelGap
            }
            let width = min(naturalWidth, plot.maxX - x)
            guard width >= Self.labelDotSize + Self.labelDotSpacing + 16 else { return nil }
            laneEnds[lane] = x + width
            return PlacedActivityLabel(
                id: span.id,
                name: name,
                color: activityColor(for: span),
                x: x,
                lane: lane,
                width: width
            )
        }
    }
}
