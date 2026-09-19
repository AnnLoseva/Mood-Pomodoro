import SwiftUI
import Charts

/// Raw hex tones from the new unified-graph design that don't already have
/// an `AppTheme` token (the scale/band/context zone backgrounds and the
/// pill chrome around the header controls). Kept local to this file rather
/// than promoted to `AppTheme` since nothing else in the app uses them.
private enum ChartPalette {
    static let scaleZone = Color(red: 0.945, green: 0.906, blue: 0.812)   // #F1E7CF
    static let bandZone = Color(red: 0.937, green: 0.894, blue: 0.784)    // #EFE4C8
    static let ctxZone = Color(red: 0.922, green: 0.875, blue: 0.757)     // #EBDFC1
    static let pillFill = Color(red: 0.925, green: 0.878, blue: 0.773)    // #ECE0C5
    static let pillBorder = Color(red: 0.839, green: 0.784, blue: 0.643)  // #D6C7A4
    static let gridLine = Color(red: 0.847, green: 0.788, blue: 0.651)    // #D8C9A6
    static let gridMid = Color(red: 0.804, green: 0.733, blue: 0.580)     // #CDBB94
    static let dashLine = Color(red: 0.875, green: 0.824, blue: 0.698)    // #DFD2B2
}



/// The quick-pick layer combinations from the new design's "пресеты" row.
private struct TimelinePreset: Identifiable {
    let key: String
    let title: String
    let layers: Set<String>
    var id: String { key }

    static let all: [TimelinePreset] = [
        TimelinePreset(key: "all", title: L("Всё", "Everything"), layers: Set(TimelineLayer.allCases.map(\.rawValue))),
        TimelinePreset(key: "mood", title: L("Настроение", "Mood"), layers: ["mood", "energy", "motivation", "sleep", "activity", "emotion"]),
        TimelinePreset(key: "food", title: L("Еда и сытость", "Food & satiety"), layers: ["hunger", "appetite", "mood", "food", "impulse"]),
        TimelinePreset(key: "rest", title: L("Сон и силы", "Sleep & energy"), layers: ["energy", "mood", "sleep", "activity", "context"])
    ]
}

/// Fixed pixel geometry for the unified plot, computed once per draw from
/// the canvas size and the currently visible time window. Shared by the
/// `Canvas` renderer and the SwiftUI overlays (tooltip/selection cards) so
/// they never drift apart.
private struct ChartLayout {
    let size: CGSize
    let win: ClosedRange<Date>
    let compact: Bool
    /// Week/month: sleep gets its own zone with a line of hours per day,
    /// on a scale from 0 up to `sleepMax` hours.
    let sleepLine: Bool
    let sleepMax: Double

    var gutter: CGFloat { compact ? 40 : 60 }
    let scaleTop: CGFloat = 4
    var scaleHeight: CGFloat { compact ? 150 : 168 }
    /// Vertical padding inside the scale zone so the "5" and "1" gridline
    /// labels (and the topmost/bottommost points) sit clear of the zone's
    /// edges instead of clipping against them.
    let labelInset: CGFloat = 11
    let bandGap: CGFloat = 6
    let bandHeight: CGFloat = 78
    let ctxGap: CGFloat = 6
    let ctxHeight: CGFloat = 18
    let tickGap: CGFloat = 8

    var x0: CGFloat { gutter }
    var x1: CGFloat { size.width }
    var plotWidth: CGFloat { max(1, x1 - x0) }

    var scaleBottom: CGFloat { scaleTop + scaleHeight }
    var sleepTop: CGFloat { scaleBottom + bandGap }
    var sleepZoneHeight: CGFloat { sleepLine ? 72 : 0 }
    var sleepBottom: CGFloat { sleepTop + sleepZoneHeight }
    var bandTop: CGFloat { (sleepLine ? sleepBottom : scaleBottom) + bandGap }
    var bandBottom: CGFloat { bandTop + bandHeight }
    var ctxTop: CGFloat { bandBottom + ctxGap }
    var ctxBottom: CGFloat { ctxTop + ctxHeight }
    var tickY: CGFloat { ctxBottom + tickGap }
    var totalHeight: CGFloat { tickY + 26 }

    var scaleRect: CGRect { CGRect(x: x0, y: scaleTop, width: plotWidth, height: scaleHeight) }
    var sleepRect: CGRect { CGRect(x: x0, y: sleepTop, width: plotWidth, height: sleepZoneHeight) }
    var bandRect: CGRect { CGRect(x: x0, y: bandTop, width: plotWidth, height: bandHeight) }
    var ctxRect: CGRect { CGRect(x: x0, y: ctxTop, width: plotWidth, height: ctxHeight) }

    private var winSpan: TimeInterval { max(1, win.upperBound.timeIntervalSince(win.lowerBound)) }

    func x(_ date: Date) -> CGFloat {
        let t = date.timeIntervalSince(win.lowerBound)
        return x0 + CGFloat(t / winSpan) * plotWidth
    }

    func date(atX px: CGFloat) -> Date {
        let frac = Double((px - x0) / plotWidth)
        return win.lowerBound.addingTimeInterval(frac * winSpan)
    }

    func y(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 1), 5)
        let frac = (5 - clamped) / 4
        let usable = scaleHeight - labelInset * 2
        return scaleTop + labelInset + CGFloat(frac) * usable
    }

    func sleepY(_ hours: Double) -> CGFloat {
        let inset: CGFloat = 9
        let frac = 1 - min(max(hours, 0), sleepMax) / max(sleepMax, 1)
        return sleepTop + inset + CGFloat(frac) * (sleepZoneHeight - inset * 2)
    }

    func eventY(_ layer: TimelineLayer) -> CGFloat {
        bandTop + CGFloat(layer.eventRowFraction) * bandHeight
    }
}

/// Raw events on a shared clock, drawn as one combined plot (scales, bands,
/// events, context) instead of stacked separate charts. Events are never
/// averaged: a month still shows every mark. The scale lines are never
/// broken by a quiet stretch — a day view breaks them only across a night's
/// sleep, and week and month draw one line through the daily averages
/// (weighted by hours, not by check-ins) unless asked for every record.
struct UnifiedTimeline: View {
    let date: Date
    let snapshot: TimelineSnapshot
    @Binding var span: TimelineSpan
    /// The day under the last tap in a week or month view, for the parent's
    /// own "Day" button to open. Nil in a day view and once the tap is gone.
    @Binding var tappedDay: Date?
    let onSelectDay: (Date) -> Void
    /// Swipe (or arrow) past the edge of the window: ask for the previous
    /// (-1) or next (+1) period, so a month can be paged through into the
    /// months around it.
    let onStep: (Int) -> Void
    let onEdit: (DiaryEditTarget, Date) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("diary.timeline.layers") private var layersRaw = "mood,sleep,food"
    @AppStorage("diary.timeline.preset") private var presetKeyRaw = ""
    @AppStorage("diary.timeline.dailyAverages") private var showsDailyAverages = true
    @State private var isSelecting = false
    @State private var cursor: Date?
    @State private var rangeSelection: ClosedRange<Date>?
    @State private var selectedMark: TimelineMark?
    @State private var dragStartDate: Date?
    @State private var visibleSpan: TimeInterval?
    @State private var scrollStart: Date?
    @State private var spanAtPinchStart: TimeInterval?
    @State private var pinchAnchor: Date?
    @State private var pinchFraction: CGFloat?
    @State private var panAnchor: Date?

    private var isCompact: Bool { sizeClass == .compact }

    private let calendar = Calendar.current
    private static let minimumSpan: TimeInterval = 15 * 60

    init(
        date: Date,
        snapshot: TimelineSnapshot,
        span: Binding<TimelineSpan>,
        tappedDay: Binding<Date?>,
        onSelectDay: @escaping (Date) -> Void,
        onStep: @escaping (Int) -> Void,
        onEdit: @escaping (DiaryEditTarget, Date) -> Void
    ) {
        self.date = date
        self.snapshot = snapshot
        self._span = span
        self._tappedDay = tappedDay
        self.onSelectDay = onSelectDay
        self.onStep = onStep
        self.onEdit = onEdit
    }

    // MARK: - Layers & presets

    private var layers: Set<String> {
        let parsed = Set(layersRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
        return parsed.isEmpty ? TimelineLayer.defaultOn : parsed
    }

    private func isOn(_ layer: TimelineLayer) -> Bool { layers.contains(layer.rawValue) }

    private func toggle(_ layer: TimelineLayer) {
        var current = layers
        if current.contains(layer.rawValue) {
            current.remove(layer.rawValue)
        } else {
            current.insert(layer.rawValue)
        }
        layersRaw = current.sorted().joined(separator: ",")
        presetKeyRaw = ""
        selectedMark = nil
    }

    private func pickPreset(_ preset: TimelinePreset) {
        layersRaw = preset.layers.sorted().joined(separator: ",")
        presetKeyRaw = preset.key
        selectedMark = nil
    }

    private var activePresetKey: String? {
        if !presetKeyRaw.isEmpty, let preset = TimelinePreset.all.first(where: { $0.key == presetKeyRaw }), preset.layers == layers {
            return presetKeyRaw
        }
        return TimelinePreset.all.first { $0.layers == layers }?.key
    }

    // MARK: - Domain & window

    private var interval: DateInterval {
        guard let component = span.calendarComponent else {
            // All time runs from the first record to the end of today; until
            // the snapshot has been built, fall back to the month in view.
            if snapshot.intervalStart > .distantPast, snapshot.intervalEnd > snapshot.intervalStart {
                return DateInterval(start: snapshot.intervalStart, end: snapshot.intervalEnd)
            }
            return calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 3600)
        }
        return calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 3600)
    }

    private var domain: ClosedRange<Date> { interval.start...interval.end }

    private var fullSpan: TimeInterval { domain.upperBound.timeIntervalSince(domain.lowerBound) }
    private var visibleLength: TimeInterval { min(visibleSpan ?? fullSpan, fullSpan) }
    private var isZoomed: Bool { visibleLength < fullSpan - 1 }
    private var canZoom: Bool { fullSpan > Self.minimumSpan * 1.5 }
    private var hasRangeSelection: Bool { rangeSelection != nil }

    private var win: ClosedRange<Date> {
        let start = scrollStart ?? domain.lowerBound
        let end = min(domain.upperBound, start.addingTimeInterval(visibleLength))
        return start...max(start, end)
    }

    private func setSpan(_ raw: TimeInterval, anchoring date: Date? = nil, atFraction fraction: CGFloat? = nil) {
        let full = fullSpan
        let clamped = min(max(raw, Self.minimumSpan), full)
        guard clamped < full - 1 else {
            visibleSpan = nil
            scrollStart = domain.lowerBound
            return
        }
        visibleSpan = clamped
        let lowest = domain.lowerBound
        let highest = max(lowest, domain.upperBound.addingTimeInterval(-clamped))
        if let date, let fraction {
            let start = date.addingTimeInterval(-Double(fraction) * clamped)
            scrollStart = min(max(start, lowest), highest)
        } else {
            let centre = (scrollStart ?? domain.lowerBound).addingTimeInterval(visibleLength / 2)
            scrollStart = min(max(centre.addingTimeInterval(-clamped / 2), lowest), highest)
        }
    }

    private func zoomBy(_ factor: Double) { setSpan(visibleLength * factor) }

    /// Slides the zoomed window; at the end of the period (or when not zoomed
    /// at all) it moves on to the neighbouring period instead.
    private func pan(_ direction: Double) {
        let lowest = domain.lowerBound
        let highest = max(lowest, domain.upperBound.addingTimeInterval(-visibleLength))
        let current = scrollStart ?? lowest
        if isZoomed {
            let atEdge = direction > 0 ? current >= highest.addingTimeInterval(-1) : current <= lowest.addingTimeInterval(1)
            if !atEdge {
                let start = current.addingTimeInterval(direction * visibleLength * 0.3)
                scrollStart = min(max(start, lowest), highest)
                return
            }
        }
        step(direction > 0 ? 1 : -1)
    }

    private func step(_ direction: Int) {
        guard span != .all else { return }
        onStep(direction)
    }

    /// A clear horizontal swipe on the chart pages to the neighbouring
    /// period — from an unzoomed window, or from a zoomed one already at
    /// that end. Anything else was a pan inside the window.
    private func handleBrowseSwipe(translation: CGSize, anchor: Date?) {
        guard span != .all,
              abs(translation.width) > 70,
              abs(translation.width) > abs(translation.height) * 1.5 else { return }
        let direction = translation.width < 0 ? 1 : -1
        if isZoomed, let anchor {
            let lowest = domain.lowerBound
            let highest = max(lowest, domain.upperBound.addingTimeInterval(-visibleLength))
            let atEdge = direction > 0 ? anchor >= highest.addingTimeInterval(-1) : anchor <= lowest.addingTimeInterval(1)
            guard atEdge else { return }
        }
        step(direction)
    }

    private func clearSelection() {
        visibleSpan = nil
        scrollStart = domain.lowerBound
        rangeSelection = nil
        selectedMark = nil
        cursor = nil
        isSelecting = false
        dragStartDate = nil
        panAnchor = nil
        pinchAnchor = nil
        pinchFraction = nil
        spanAtPinchStart = nil
    }

    private func clearRange() {
        rangeSelection = nil
        dragStartDate = nil
    }

    private func dismissInspect() {
        cursor = nil
        selectedMark = nil
    }

    // MARK: - Marks (from the prepared snapshot; pan/zoom only filters)

    private var marks: [TimelineMark] {
        snapshot.marks.filter { isOn($0.layer) }
    }

    /// Week and month draw one point per day by default; a day always
    /// draws what was recorded.
    private var usesDailyAverages: Bool { span != .day && showsDailyAverages }

    /// Every recorded value on the visible layers, whatever is drawn.
    private var recordedPoints: [TimelineMark] { marks.filter { $0.layer.isNumeric && $0.value != nil } }
    /// The points the scale lines are drawn through.
    private var numericPoints: [TimelineMark] {
        guard usesDailyAverages else { return recordedPoints }
        return TimelineLayer.numericLayers.filter(isOn).flatMap { snapshot.dailyAverages[$0] ?? [] }
    }
    private var eventPoints: [TimelineMark] { marks.filter(\.layer.isEvent) }
    /// Week and month draw sleep as a line of hours, not as bands.
    private var bandMarks: [TimelineMark] {
        marks.filter { $0.layer.isInterval && !($0.layer == .sleep && span != .day) }
    }

    private var showsSleepLine: Bool { span != .day && isOn(.sleep) && !snapshot.sleepDays.isEmpty }

    /// Room for the longest day, and never squeezed below a ten-hour scale.
    private var sleepMax: Double {
        max(10, ceil(snapshot.sleepDays.compactMap(\.value).max() ?? 0))
    }

    private func layout(size: CGSize) -> ChartLayout {
        ChartLayout(size: size, win: win, compact: isCompact, sleepLine: showsSleepLine, sleepMax: sleepMax)
    }

    /// Where each event mark actually draws. Several emotions felt at once
    /// are one entry recorded at one instant — several marks sharing the
    /// same layer and timestamp — so left as-is they'd stack exactly on top
    /// of each other and only the last one drawn would ever be visible or
    /// tappable. This fans same-moment marks out sideways along their lane
    /// instead. Shared by drawing and hit-testing so a tap always lands on
    /// what's actually on screen.
    private func eventPositions(layout: ChartLayout) -> [(mark: TimelineMark, point: CGPoint)] {
        let spacing: CGFloat = 22
        var order: [String] = []
        var groups: [String: [TimelineMark]] = [:]
        for mark in eventPoints {
            let key = "\(mark.layer.rawValue)|\(mark.date.timeIntervalSinceReferenceDate)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(mark)
        }
        var out: [(mark: TimelineMark, point: CGPoint)] = []
        for key in order {
            guard let group = groups[key], let first = group.first else { continue }
            let baseX = layout.x(first.date)
            let y = layout.eventY(first.layer)
            let startX = baseX - CGFloat(group.count - 1) * spacing / 2
            for (index, mark) in group.enumerated() {
                out.append((mark, CGPoint(x: startX + CGFloat(index) * spacing, y: y)))
            }
        }
        return out
    }

    private func numericGroups(for layer: TimelineLayer) -> [[TimelineMark]] {
        if usesDailyAverages {
            // One line, never broken: a quiet day is not a gap.
            guard let days = snapshot.dailyAverages[layer], !days.isEmpty else { return [] }
            return [days]
        }
        return snapshot.numericGroups[layer] ?? []
    }

    private func valueAt(_ layer: TimelineLayer, _ time: Date, snap: Bool = false) -> Double? {
        // The groups are already sorted and precomputed once per snapshot —
        // reusing them here avoids re-filtering and re-sorting the whole
        // mark list on every call, which runs on every canvas redraw (i.e.
        // every frame of a pan/pinch gesture).
        let groups = numericGroups(for: layer)
        for group in groups {
            for (a, b) in zip(group, group.dropFirst()) {
                let gap = b.date.timeIntervalSince(a.date)
                if time >= a.date && time <= b.date, gap > 0 {
                    let k = time.timeIntervalSince(a.date) / gap
                    return (a.value ?? 0) + ((b.value ?? 0) - (a.value ?? 0)) * k
                }
            }
        }
        guard snap else { return nil }
        let window: TimeInterval = span == .day ? 20 * 60 : 12 * 3600
        let pts = groups.flatMap { $0 }
        if let nearest = pts.min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
           abs(nearest.date.timeIntervalSince(time)) <= window {
            return nearest.value
        }
        return nil
    }

    private var contextDays: [DayAggregate] { snapshot.contextDays }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            presetsRow
            chipsRow
            if enabledChartLayers.isEmpty && !isOn(.context) {
                Text(L("Включи хотя бы один слой.", "Turn on at least one layer."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if marks.isEmpty && !(isOn(.context) && !contextDays.isEmpty) {
                Text(L("За этот период нет отметок на выбранных слоях.", "Nothing on the chosen layers in this period."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                chartCard
                if isOn(.activity) { activityLegend }
                footerBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 12 : 18)
        .parchmentCard(padding: 0)
        .preference(key: TimelineBlocksScrollKey.self, value: isSelecting)
        .onChange(of: date) { _, _ in clearSelection() }
        .onChange(of: span) { _, _ in clearSelection() }
        .onChange(of: cursor) { _, newValue in
            tappedDay = span == .day ? nil : newValue.map { calendar.startOfDay(for: $0) }
        }
    }

    private var enabledChartLayers: [TimelineLayer] {
        TimelineLayer.allCases.filter { $0 != .context && isOn($0) }
    }

    // MARK: - Header

    private var periodCaption: String {
        if span == .day {
            var text = DateFormatting.fullDate(win.lowerBound)
            if isZoomed { text += " · \(DateFormatting.time(win.lowerBound)) – \(DateFormatting.time(win.upperBound))" }
            return text
        }
        return span.title + " · " + DateFormatting.compactDate(win.lowerBound) + " – " + DateFormatting.compactDate(win.upperBound)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Общий график", "Timeline"))
                    .font(.lora(16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(periodCaption)
                    .font(.lora(11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isCompact {
                FlowLayout(spacing: 8) {
                    spanPicker
                    if canZoom { navCluster }
                    if span != .day { averagesToggle }
                    selectToggle
                }
            } else {
                HStack(spacing: 8) {
                    spanPicker
                    if canZoom { navCluster }
                    if span != .day { averagesToggle }
                    selectToggle
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var spanPicker: some View {
        HStack(spacing: 3) {
            ForEach(TimelineSpan.allCases) { item in
                let selected = item == span
                Button {
                    // A tap on a week or month opens that very day.
                    if item == .day, span != .day, let cursor {
                        onSelectDay(calendar.startOfDay(for: cursor))
                    } else {
                        span = item
                    }
                } label: {
                    Text(item.title)
                        .font(.lora(11.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppTheme.parchmentCard : AppTheme.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(selected ? AppTheme.forest : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(ChartPalette.pillFill))
        .overlay(Capsule().stroke(ChartPalette.pillBorder, lineWidth: 1))
    }

    private var navCluster: some View {
        HStack(spacing: 2) {
            navButton("chevron.left", label: L("Назад", "Back")) { pan(-1) }
                .disabled(isSelecting || (span == .all && !isZoomed))
            navButton("minus", label: L("Отдалить", "Zoom out")) { zoomBy(1.55) }
                .disabled(!isZoomed || isSelecting)
            navButton("plus", label: L("Приблизить", "Zoom in")) { zoomBy(0.65) }
                .disabled(isSelecting)
            navButton("chevron.right", label: L("Вперёд", "Forward")) { pan(1) }
                .disabled(isSelecting || (span == .all && !isZoomed))
        }
        .padding(3)
        .background(Capsule().fill(ChartPalette.pillFill))
        .overlay(Capsule().stroke(ChartPalette.pillBorder, lineWidth: 1))
        .opacity(isSelecting ? 0.45 : 1)
    }

    private var selectToggle: some View {
        Button {
            isSelecting.toggle()
            dragStartDate = nil
            panAnchor = nil
        } label: {
            Text(L("Выделить", "Select"))
                .font(.lora(11.5, weight: isSelecting ? .semibold : .regular))
                .foregroundStyle(isSelecting ? AppTheme.parchmentCard : AppTheme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelecting ? AppTheme.forest : ChartPalette.pillFill))
                .overlay(Capsule().stroke(isSelecting ? AppTheme.forest : ChartPalette.pillBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Режим выделения", "Selection mode"))
        .accessibilityValue(isSelecting ? L("включён", "on") : L("выключен", "off"))
    }

    private var averagesToggle: some View {
        Button {
            showsDailyAverages.toggle()
            selectedMark = nil
        } label: {
            Text(L("Среднее за день", "Daily average"))
                .font(.lora(11.5, weight: showsDailyAverages ? .semibold : .regular))
                .foregroundStyle(showsDailyAverages ? AppTheme.parchmentCard : AppTheme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(showsDailyAverages ? AppTheme.forest : ChartPalette.pillFill))
                .overlay(Capsule().stroke(showsDailyAverages ? AppTheme.forest : ChartPalette.pillBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Среднее за день", "Daily average"))
        .accessibilityValue(showsDailyAverages ? L("включено", "on") : L("выключено", "off"))
    }

    private func navButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Presets & chips

    private var presetsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isCompact {
                Text(L("пресеты", "presets"))
                    .font(.loraItalic(10.5))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            HStack(alignment: .top, spacing: 8) {
                if !isCompact {
                    Text(L("пресеты", "presets"))
                        .font(.loraItalic(10.5))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 56, alignment: .leading)
                        .padding(.top, 5)
                }
                FlowLayout(spacing: 6) {
                    ForEach(TimelinePreset.all) { preset in
                        let selected = activePresetKey == preset.key
                        Button { pickPreset(preset) } label: {
                            Text(preset.title)
                                .font(.lora(11.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? AppTheme.parchmentCard : AppTheme.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(selected ? AppTheme.forest : ChartPalette.pillFill))
                                .overlay(Capsule().stroke(selected ? AppTheme.forest : ChartPalette.pillBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    if hasRangeSelection {
                        Button(L("Сбросить выделение", "Clear selection"), action: clearRange)
                            .font(.lora(11.5))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(ChartPalette.pillFill))
                            .overlay(Capsule().stroke(ChartPalette.pillBorder, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var chipsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isCompact {
                Text(L("слои", "layers"))
                    .font(.loraItalic(10.5))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            HStack(alignment: .top, spacing: 6) {
                if !isCompact {
                    Text(L("слои", "layers"))
                        .font(.loraItalic(10.5))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 56, alignment: .leading)
                        .padding(.top, 5)
                }
                FlowLayout(spacing: 6) {
                    ForEach(TimelineLayer.allCases) { layer in
                        let on = isOn(layer)
                        Button { toggle(layer) } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(on ? layer.color : AppTheme.border)
                                    .frame(width: 7, height: 7)
                                Text(layer.title)
                                    .font(.lora(11.5, weight: on ? .semibold : .regular))
                                    .foregroundStyle(on ? layer.textColor : AppTheme.inkSoft)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(on ? layer.color.opacity(0.15) : ChartPalette.pillFill.opacity(0.55)))
                            .overlay(Capsule().stroke(on ? layer.color.opacity(0.5) : ChartPalette.pillBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(layer.title)
                        .accessibilityValue(on ? L("показан", "shown") : L("скрыт", "hidden"))
                    }
                }
            }
        }
    }

    private var activityLegend: some View {
        FlowLayout(spacing: 8) {
            ForEach(SessionType.allCases) { type in
                Label {
                    Text(type.shortLabel)
                } icon: {
                    Circle().fill(type.color).frame(width: 7, height: 7)
                }
                .font(.lora(10))
                .foregroundStyle(AppTheme.inkSoft)
            }
            Text(SessionType.unassignedLabel)
                .font(.lora(10))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let layout = layout(size: proxy.size)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(context: &context, layout: layout)
                    }
                    .frame(width: proxy.size.width, height: layout.totalHeight)

                    TimelineChartGestures(
                        mode: isSelecting ? .select : .browse,
                        panEnabled: isSelecting || isZoomed || span != .all,
                        pinchEnabled: !isSelecting && canZoom,
                        onTap: { handleTap(at: $0, layout: layout) },
                        onPanChanged: { point, translation in
                            if isSelecting {
                                handleSelectDrag(at: point, layout: layout)
                            } else {
                                handleBrowsePan(translation: translation, layout: layout)
                            }
                        },
                        onPanEnded: { point, translation in
                            if isSelecting {
                                handleSelectDragEnd(at: point, translation: translation, layout: layout)
                            } else {
                                let anchor = panAnchor
                                panAnchor = nil
                                handleBrowseSwipe(translation: translation, anchor: anchor)
                            }
                        },
                        onPinchChanged: { scale, center in
                            handlePinch(scale: scale, center: center, layout: layout)
                        },
                        onPinchEnded: {
                            spanAtPinchStart = nil
                            pinchAnchor = nil
                            pinchFraction = nil
                        }
                    )
                    .frame(width: proxy.size.width, height: layout.totalHeight)
                }
            }
            .frame(height: layout(size: .zero).totalHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelecting ? AppTheme.forest.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )

            if let cursor {
                inspectCard(for: cursor, mark: selectedMark)
            } else if let mark = selectedMark {
                inspectCard(for: mark.date, mark: mark)
            }
        }
    }

    private func handleTap(at point: CGPoint, layout: ChartLayout) {
        let clampedX = min(max(point.x, layout.x0), layout.x1)
        let time = layout.date(atX: clampedX)
        cursor = time
        selectedMark = hitTest(at: CGPoint(x: clampedX, y: point.y), layout: layout)
        if selectedMark == nil, layout.ctxRect.insetBy(dx: -6, dy: -6).contains(point) {
            onEdit(.support(calendar.startOfDay(for: time)), time)
        }
    }

    private func handleBrowsePan(translation: CGSize, layout: ChartLayout) {
        guard isZoomed else { return }
        if panAnchor == nil { panAnchor = scrollStart ?? domain.lowerBound }
        let delta = -Double(translation.width) / Double(layout.plotWidth) * visibleLength
        let start = (panAnchor ?? domain.lowerBound).addingTimeInterval(delta)
        let lowest = domain.lowerBound
        let highest = max(lowest, domain.upperBound.addingTimeInterval(-visibleLength))
        scrollStart = min(max(start, lowest), highest)
    }

    private func handleSelectDrag(at point: CGPoint, layout: ChartLayout) {
        selectedMark = nil
        let clampedX = min(max(point.x, layout.x0), layout.x1)
        let time = layout.date(atX: clampedX)
        if dragStartDate == nil { dragStartDate = time }
        cursor = time
        if let start = dragStartDate, abs(clampedX - layout.x(start)) > 6 {
            rangeSelection = min(start, time)...max(start, time)
        }
    }

    private func handleSelectDragEnd(at point: CGPoint, translation: CGSize, layout: ChartLayout) {
        defer { dragStartDate = nil }
        let clampedX = min(max(point.x, layout.x0), layout.x1)
        guard let start = dragStartDate else { return }
        if abs(clampedX - layout.x(start)) < 6, hypot(translation.width, translation.height) < 10 {
            handleTap(at: point, layout: layout)
        }
    }

    private func handlePinch(scale: CGFloat, center: CGPoint, layout: ChartLayout) {
        let base = spanAtPinchStart ?? visibleLength
        if spanAtPinchStart == nil {
            spanAtPinchStart = base
            let clampedX = min(max(center.x, layout.x0), layout.x1)
            pinchAnchor = layout.date(atX: clampedX)
            pinchFraction = (clampedX - layout.x0) / layout.plotWidth
        }
        setSpan(base / TimeInterval(scale), anchoring: pinchAnchor, atFraction: pinchFraction)
    }

    private func hitTest(at point: CGPoint, layout: ChartLayout) -> TimelineMark? {
        if layout.scaleRect.insetBy(dx: -10, dy: -10).contains(point) {
            var best: (TimelineMark, CGFloat)?
            for mark in numericPoints {
                let p = CGPoint(x: layout.x(mark.date), y: layout.y(mark.value ?? 0))
                let d = hypot(p.x - point.x, p.y - point.y)
                if d < 26, best == nil || d < best!.1 { best = (mark, d) }
            }
            return best?.0
        }
        if layout.sleepLine, layout.sleepRect.insetBy(dx: -10, dy: -10).contains(point) {
            var best: (TimelineMark, CGFloat)?
            for mark in snapshot.sleepDays {
                let p = CGPoint(x: layout.x(mark.date), y: layout.sleepY(mark.value ?? 0))
                let d = hypot(p.x - point.x, p.y - point.y)
                if d < 26, best == nil || d < best!.1 { best = (mark, d) }
            }
            return best?.0
        }
        if layout.bandRect.insetBy(dx: -10, dy: -10).contains(point) {
            var best: (TimelineMark, CGFloat)?
            for (mark, p) in eventPositions(layout: layout) {
                let d = hypot(p.x - point.x, p.y - point.y)
                if d < 14, best == nil || d < best!.1 { best = (mark, d) }
            }
            if let hit = best?.0 { return hit }
            let time = layout.date(atX: point.x)
            return bandMarks.first { time >= $0.date && time <= ($0.end ?? $0.date) }
        }
        return nil
    }

    // MARK: - Drawing

    private func draw(context: inout GraphicsContext, layout: ChartLayout) {
        // Zone backgrounds.
        context.fill(Path(roundedRect: layout.scaleRect, cornerRadius: 10), with: .color(ChartPalette.scaleZone))
        context.fill(Path(roundedRect: layout.bandRect, cornerRadius: 10), with: .color(ChartPalette.bandZone))
        if layout.sleepLine { drawSleepLine(context: &context, layout: layout) }
        context.fill(Path(roundedRect: layout.ctxRect, cornerRadius: 7), with: .color(ChartPalette.ctxZone))

        // Y gridlines + labels for the 1–5 scale.
        for i in 1...5 {
            let y = layout.y(Double(i))
            var line = Path()
            line.move(to: CGPoint(x: layout.x0, y: y))
            line.addLine(to: CGPoint(x: layout.x1, y: y))
            context.stroke(line, with: .color(i == 3 ? ChartPalette.gridMid : ChartPalette.gridLine), lineWidth: 1)
            context.draw(
                Text("\(i)").font(.lora(10)).foregroundStyle(AppTheme.inkSoft),
                at: CGPoint(x: layout.gutter - 6, y: y), anchor: .trailing
            )
        }

        // Row labels for the events lane.
        let rowLayers: [TimelineLayer] = [.emotion, .food, .impulse]
        for layer in rowLayers {
            context.draw(
                Text(laneCaption(layer, compact: layout.compact)).font(.lora(9.5)).foregroundStyle(AppTheme.inkSoft.opacity(0.85)),
                at: CGPoint(x: layout.gutter - 6, y: layout.eventY(layer)), anchor: .trailing
            )
        }
        context.draw(
            Text(layout.compact ? L("Конт.", "Ctx") : L("Контекст", "Context"))
                .font(.lora(9.5)).foregroundStyle(AppTheme.inkSoft.opacity(0.85)),
            at: CGPoint(x: layout.gutter - 6, y: layout.ctxRect.midY), anchor: .trailing
        )

        // Bands + events, clipped to the events lane.
        context.drawLayer { ctx in
            ctx.clip(to: Path(layout.bandRect))
            for band in bandMarks {
                let bx0 = max(layout.x(band.date), layout.x0)
                let bx1 = min(layout.x(band.end ?? band.date), layout.x1)
                guard bx1 - bx0 > 0.5 else { continue }
                let rect = CGRect(x: bx0, y: layout.bandTop + 3, width: bx1 - bx0, height: layout.bandHeight - 6)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(band.color.opacity(0.24)))
            }
            for (mark, p) in eventPositions(layout: layout) {
                // A long window holds far more marks than fit on screen.
                guard p.x > layout.x0 - 14, p.x < layout.x1 + 14 else { continue }
                if let art = mark.art {
                    ctx.draw(Image(art), in: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24))
                } else {
                    let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                    ctx.fill(dot, with: .color(mark.color))
                    ctx.stroke(dot, with: .color(AppTheme.parchmentCard), lineWidth: 1.6)
                }
            }
        }

        // Numeric scale lines + points, clipped to the scale zone. Each
        // series is one continuous smooth curve, halo first so it reads
        // against the grid and against other lines. Where two series land
        // on the same value the later one simply sits on top — plainer
        // than the dashed "candy stripe" this used to switch to on overlap,
        // which read as the line tearing apart wherever curves crossed.
        context.drawLayer { ctx in
            ctx.clip(to: Path(layout.scaleRect))
            let activeScales = TimelineLayer.numericLayers.filter(isOn)
            for layer in activeScales {
                for group in numericGroups(for: layer) where group.count > 1 {
                    let points = group.map { CGPoint(x: layout.x($0.date), y: layout.y($0.value ?? 0)) }
                    let path = smoothPath(points)
                    ctx.stroke(path, with: .color(AppTheme.parchmentCard), lineWidth: 6.4)
                    ctx.stroke(path, with: .color(layer.color), lineWidth: 3)
                }
            }
            for mark in numericPoints {
                let p = CGPoint(x: layout.x(mark.date), y: layout.y(mark.value ?? 0))
                let circle = Path(ellipseIn: CGRect(x: p.x - 4.2, y: p.y - 4.2, width: 8.4, height: 8.4))
                ctx.fill(circle, with: .color(mark.color))
                ctx.stroke(circle, with: .color(AppTheme.parchmentCard), lineWidth: 1.6)
            }
            // Mood-face art in the gutter when mood is the only active scale.
            if activeScales == [.mood], !layout.compact {
                for step in 1...5 {
                    if let name = Mood.atScale(step)?.imageName {
                        let y = layout.y(Double(step))
                        ctx.draw(Image(name), in: CGRect(x: layout.gutter - 30, y: y - 11, width: 22, height: 22))
                    }
                }
            }
        }

        // Context ribbon cells.
        context.drawLayer { ctx in
            ctx.clip(to: Path(layout.ctxRect))
            for day in contextDays {
                let start = calendar.startOfDay(for: day.day)
                guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                let cx0 = max(layout.x(start), layout.x0)
                let cx1 = min(layout.x(end), layout.x1)
                guard cx1 - cx0 > 0.5 else { continue }
                let rect = CGRect(x: cx0 + 1, y: layout.ctxTop + 2, width: cx1 - cx0 - 2, height: layout.ctxHeight - 4)
                let fill: Color
                let stroke: Color
                if day.isPeriodDay {
                    fill = AppTheme.rust.opacity(0.2); stroke = AppTheme.rust.opacity(0.45)
                } else if day.support == .taken {
                    fill = AppTheme.forest.opacity(0.15); stroke = AppTheme.forest.opacity(0.35)
                } else {
                    fill = ChartPalette.pillFill.opacity(0.5); stroke = ChartPalette.pillBorder
                }
                let shape = Path(roundedRect: rect, cornerRadius: 4)
                ctx.fill(shape, with: .color(fill))
                ctx.stroke(shape, with: .color(stroke), lineWidth: 0.9)
            }
        }

        // X-axis ticks. The label's x is clamped so it never overhangs the
        // canvas edges (a centered label at the first/last tick otherwise
        // gets clipped by the drawing surface's own bounds).
        for tick in ticks(layout: layout) {
            var line = Path()
            line.move(to: CGPoint(x: tick.x, y: layout.tickY))
            line.addLine(to: CGPoint(x: tick.x, y: layout.tickY + 5))
            context.stroke(line, with: .color(ChartPalette.pillBorder), lineWidth: 1)
            let labelX = min(max(tick.x, layout.x0 + 18), layout.x1 - 18)
            context.draw(
                Text(tick.label).font(.lora(9.5)).foregroundStyle(AppTheme.inkSoft),
                at: CGPoint(x: labelX, y: layout.tickY + 12), anchor: .top
            )
        }

        // Range selection shading.
        if let range = rangeSelection {
            let rx0 = max(layout.x(range.lowerBound), layout.x0)
            let rx1 = min(layout.x(range.upperBound), layout.x1)
            if rx1 > rx0 {
                let rect = CGRect(x: rx0, y: layout.scaleTop, width: rx1 - rx0, height: layout.ctxBottom - layout.scaleTop)
                context.fill(Path(rect), with: .color(AppTheme.ink.opacity(0.07)))
                for edgeX in [rx0, rx1] {
                    var edge = Path()
                    edge.move(to: CGPoint(x: edgeX, y: layout.scaleTop))
                    edge.addLine(to: CGPoint(x: edgeX, y: layout.ctxBottom))
                    context.stroke(edge, with: .color(AppTheme.inkSoft), lineWidth: 1)
                }
            }
        }

        // Cursor line + dots.
        if let cursor, cursor >= win.lowerBound && cursor <= win.upperBound {
            let cx = layout.x(cursor)
            var line = Path()
            line.move(to: CGPoint(x: cx, y: layout.scaleTop))
            line.addLine(to: CGPoint(x: cx, y: layout.ctxBottom))
            context.stroke(line, with: .color(AppTheme.ink.opacity(0.45)), lineWidth: 1.1)
            for layer in TimelineLayer.numericLayers.filter(isOn) {
                guard let value = valueAt(layer, cursor, snap: true) else { continue }
                let p = CGPoint(x: cx, y: layout.y(value))
                let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                context.fill(dot, with: .color(layer.color))
                context.stroke(dot, with: .color(AppTheme.parchmentCard), lineWidth: 2)
            }
        }
    }

    /// Hours slept per day as one unbroken line, so a short night shows as a
    /// dip. The scale marks are plain reference points, not a target.
    private func drawSleepLine(context: inout GraphicsContext, layout: ChartLayout) {
        context.fill(Path(roundedRect: layout.sleepRect, cornerRadius: 10), with: .color(ChartPalette.scaleZone))
        for hours in stride(from: 4.0, through: layout.sleepMax, by: 4.0) {
            let y = layout.sleepY(hours)
            var line = Path()
            line.move(to: CGPoint(x: layout.x0, y: y))
            line.addLine(to: CGPoint(x: layout.x1, y: y))
            context.stroke(line, with: .color(ChartPalette.gridLine), lineWidth: 1)
            context.draw(
                Text(L("\(Int(hours)) ч", "\(Int(hours)) h")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft),
                at: CGPoint(x: layout.gutter - 6, y: y), anchor: .trailing
            )
        }
        context.draw(
            Text(TimelineLayer.sleep.title).font(.lora(9.5)).foregroundStyle(AppTheme.inkSoft.opacity(0.85)),
            at: CGPoint(x: layout.gutter - 6, y: layout.sleepRect.minY + 8), anchor: .trailing
        )
        context.drawLayer { ctx in
            ctx.clip(to: Path(layout.sleepRect))
            let points = snapshot.sleepDays.map { CGPoint(x: layout.x($0.date), y: layout.sleepY($0.value ?? 0)) }
            if points.count > 1 {
                let path = smoothPath(points)
                ctx.stroke(path, with: .color(AppTheme.parchmentCard), lineWidth: 6.4)
                ctx.stroke(path, with: .color(TimelineLayer.sleep.color), lineWidth: 3)
            }
            for p in points {
                let circle = Path(ellipseIn: CGRect(x: p.x - 4.2, y: p.y - 4.2, width: 8.4, height: 8.4))
                ctx.fill(circle, with: .color(TimelineLayer.sleep.color))
                ctx.stroke(circle, with: .color(AppTheme.parchmentCard), lineWidth: 1.6)
            }
        }
    }

    /// Catmull-Rom → cubic Bézier, matching the smooth curve style of the design.
    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func laneCaption(_ layer: TimelineLayer, compact: Bool) -> String {
        guard compact else { return layer.title }
        switch layer {
        case .emotion: return L("Эмоц.", "Emot.")
        case .impulse: return L("Имп.", "Imp.")
        default: return layer.title
        }
    }


    private struct Tick { let x: CGFloat; let label: String }

    private func ticks(layout: ChartLayout) -> [Tick] {
        var out: [Tick] = []
        let length = win.upperBound.timeIntervalSince(win.lowerBound)
        if span == .day || length <= 26 * 3600 {
            let stepChoices: [TimeInterval] = [900, 1800, 3600, 7200, 10800, 21600]
            let step = stepChoices.first { length / $0 <= 8 } ?? 21600
            var t = (win.lowerBound.timeIntervalSinceReferenceDate / step).rounded(.up) * step
            let end = win.upperBound.timeIntervalSinceReferenceDate
            while t <= end + 1 {
                let d = Date(timeIntervalSinceReferenceDate: t)
                out.append(Tick(x: layout.x(d), label: DateFormatting.time(d)))
                t += step
            }
        } else {
            let dayCount = length / 86400
            if dayCount > 62 {
                // Months, thinned so they never crowd: about seven labels.
                let every = max(1, Int(ceil(dayCount / 30 / 7)))
                var idx = 0
                var month = calendar.dateInterval(of: .month, for: win.lowerBound)?.start ?? calendar.startOfDay(for: win.lowerBound)
                while month < win.upperBound {
                    if idx % every == 0 {
                        out.append(Tick(x: layout.x(month), label: month.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(AppLanguage.current.locale))))
                    }
                    idx += 1
                    month = calendar.date(byAdding: .month, value: 1, to: month) ?? win.upperBound
                }
            } else {
                let every = dayCount > 16 ? 3 : 1
                var idx = 0
                var day = calendar.startOfDay(for: win.lowerBound)
                while day < win.upperBound {
                    if idx % every == 0 {
                        out.append(Tick(x: layout.x(day), label: DateFormatting.compactDate(day)))
                    }
                    idx += 1
                    day = calendar.date(byAdding: .day, value: 1, to: day) ?? win.upperBound
                }
            }
        }
        return out.filter { $0.x >= layout.x0 - 1 && $0.x <= layout.x1 + 1 }
    }

    // MARK: - Inspect overlay

    private func inspectCard(for cursor: Date, mark: TimelineMark?) -> some View {
        let activeScales = TimelineLayer.numericLayers.filter(isOn)
        let notes = tooltipNotes(for: cursor)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(span == .day ? DateFormatting.time(cursor) : DateFormatting.compactDate(cursor))
                    .font(.lora(13, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 6)
                Button(action: dismissInspect) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(ChartPalette.pillFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Закрыть", "Close"))
            }
            ForEach(activeScales) { layer in
                HStack(spacing: 6) {
                    Circle().fill(layer.color).frame(width: 7, height: 7)
                    Text(layer.title)
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 4)
                    if let value = valueAt(layer, cursor, snap: true) {
                        Text(String(format: "%.1f", value))
                            .font(.lora(12, weight: .semibold))
                            .foregroundStyle(layer.textColor)
                    } else {
                        Text("—").font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
            if showsSleepLine {
                let day = snapshot.sleepDays.first { calendar.isDate($0.date, inSameDayAs: cursor) }
                HStack(spacing: 6) {
                    Circle().fill(TimelineLayer.sleep.color).frame(width: 7, height: 7)
                    Text(TimelineLayer.sleep.title)
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 4)
                    if let hours = day?.value {
                        Text(DurationFormatting.compact(hours * 3600))
                            .font(.lora(12, weight: .semibold))
                            .foregroundStyle(TimelineLayer.sleep.textColor)
                    } else {
                        Text("—").font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
            if let mark {
                Divider().overlay(ChartPalette.dashLine)
                Text(combinedTitle(for: mark))
                    .font(.lora(12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !notes.isEmpty {
                Divider().overlay(ChartPalette.dashLine)
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(.lora(10.5))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let mark, mark.target != nil {
                Button {
                    if let target = mark.target { onEdit(target, mark.date) }
                    dismissInspect()
                } label: {
                    Text(L("Открыть запись", "Open entry"))
                        .font(.lora(11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.parchmentCard)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(AppTheme.forest))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.parchmentCard))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
    }

    /// Several emotions felt at once are one entry, not one each — naming
    /// only the mark nearest the tap would silently drop the others. Marks
    /// sharing the same entry (`target`) get listed together instead.
    private func combinedTitle(for mark: TimelineMark) -> String {
        guard mark.layer == .emotion, let target = mark.target else { return mark.title }
        let siblings = marks.filter { $0.layer == .emotion && $0.target == target }
        guard siblings.count > 1 else { return mark.title }
        return siblings.map(\.title).joined(separator: " · ")
    }

    private func tooltipNotes(for cursor: Date) -> [String] {
        var notes: [String] = []
        for band in bandMarks where cursor >= band.date && cursor <= (band.end ?? band.date) {
            notes.append(band.title)
        }
        let near: TimeInterval = span == .day ? 20 * 60 : 12 * 3600
        for event in eventPoints where abs(event.date.timeIntervalSince(cursor)) <= near {
            notes.append(event.title)
        }
        if isOn(.context), let day = contextDays.first(where: { calendar.isDate($0.day, inSameDayAs: cursor) }) {
            var line = day.support.map { "💊 \($0.label)" } ?? L("💊 Не отмечено", "💊 Not recorded")
            if day.isPeriodDay { line += " · " + L("менструация", "period") }
            else if let cycleDay = day.cycleDay { line += " · " + L("день цикла \(cycleDay)", "cycle day \(cycleDay)") }
            notes.append(line)
        }
        return Array(notes.prefix(4))
    }

    // MARK: - Footer

    private var footerRange: ClosedRange<Date> { rangeSelection ?? win }

    private var footTitle: String {
        if rangeSelection != nil { return L("Выделено", "Selected") }
        if span == .day { return isZoomed ? L("Видимый отрезок", "Visible range") : L("Весь день", "Whole day") }
        switch span {
        case .week: return L("Неделя целиком", "Whole week")
        case .all: return L("Всё время", "All time")
        default: return L("Месяц целиком", "Whole month")
        }
    }

    private var footSub: String {
        let range = footerRange
        if rangeSelection != nil {
            return DurationFormatting.compact(range.upperBound.timeIntervalSince(range.lowerBound))
        }
        if span == .day {
            return DateFormatting.time(range.lowerBound) + " – " + DateFormatting.time(range.upperBound)
        }
        let days = max(1, Int(range.upperBound.timeIntervalSince(range.lowerBound) / 86400))
        return L("\(days) дн. в срезе", "\(days) days in range")
    }

    private func average(_ layer: TimelineLayer, in range: ClosedRange<Date>) -> Double? {
        let pts = recordedPoints.filter { $0.layer == layer && $0.date >= range.lowerBound && $0.date <= range.upperBound }
        guard !pts.isEmpty else { return nil }
        return pts.reduce(0.0) { $0 + ($1.value ?? 0) } / Double(pts.count)
    }

    private var footerHint: String {
        if isSelecting {
            return L("Веди пальцем по графику — выделишь отрезок. Масштаб и прокрутка страницы выключены.", "Drag across the graph to select a range. Zoom and page scrolling are off.")
        }
        return L("Нажми на график — увидишь все слои в этой точке. Один палец двигает таймлайн, два пальца приближают. Страницу листай сверху вниз.", "Tap the graph to see every layer at that moment. One finger pans the timeline, two fingers zoom. Swipe up or down to scroll the page.")
    }

    @ViewBuilder
    private func footerPills(in range: ClosedRange<Date>) -> some View {
        ForEach(TimelineLayer.numericLayers.filter(isOn)) { layer in
            footerPill(dotColor: layer.color, title: layer.title, value: average(layer, in: range).map { String(format: "%.1f", $0) } ?? "—", valueColor: layer.textColor)
        }
        if isOn(.sleep), span != .day {
            // A total over a week says nothing; what a day usually held does.
            let days = snapshot.sleepDays.filter { $0.date >= range.lowerBound && $0.date <= range.upperBound }
            let mean = days.isEmpty ? nil : days.reduce(0.0) { $0 + ($1.value ?? 0) } / Double(days.count)
            footerPill(
                dotColor: TimelineLayer.sleep.color,
                title: L("Сон в среднем", "Sleep, average"),
                value: mean.map { DurationFormatting.compact($0 * 3600) } ?? "—",
                valueColor: TimelineLayer.sleep.textColor
            )
        } else if isOn(.sleep) {
            let mins = bandMarks.filter { $0.layer == .sleep }
                .reduce(0.0) { $0 + max(0, min($1.end ?? $1.date, range.upperBound).timeIntervalSince(max($1.date, range.lowerBound))) }
            footerPill(dotColor: TimelineLayer.sleep.color, title: L("Сон", "Sleep"), value: mins > 0 ? DurationFormatting.compact(mins) : "—", valueColor: TimelineLayer.sleep.textColor)
        }
        if isOn(.activity) {
            let mins = bandMarks.filter { $0.layer == .activity }
                .reduce(0.0) { $0 + max(0, min($1.end ?? $1.date, range.upperBound).timeIntervalSince(max($1.date, range.lowerBound))) }
            footerPill(dotColor: TimelineLayer.activity.color, title: L("Активно", "Active"), value: mins > 0 ? DurationFormatting.compact(mins) : "—", valueColor: TimelineLayer.activity.textColor)
        }
        ForEach([TimelineLayer.emotion, .food, .impulse].filter(isOn)) { layer in
            let n = eventPoints.filter { $0.layer == layer && $0.date >= range.lowerBound && $0.date <= range.upperBound }.count
            footerPill(dotColor: layer.color, title: layer.title, value: "\(n)", valueColor: layer.textColor)
        }
    }

    private var footerBar: some View {
        let range = footerRange

        return VStack(alignment: .leading, spacing: 10) {
            if isCompact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(footTitle).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                    Text(footSub).font(.lora(10.5)).foregroundStyle(AppTheme.inkSoft)
                }
                FlowLayout(spacing: 6) { footerPills(in: range) }
                Text(footerHint)
                    .font(.loraItalic(10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(footTitle).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        Text(footSub).font(.lora(10.5)).foregroundStyle(AppTheme.inkSoft)
                    }
                    .frame(width: 118, alignment: .leading)

                    FlowLayout(spacing: 6) { footerPills(in: range) }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(footerHint)
                        .font(.loraItalic(10))
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(width: 160, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ChartPalette.scaleZone))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ChartPalette.dashLine, lineWidth: 1))
    }

    private func footerPill(dotColor: Color, title: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(title).font(.lora(11)).foregroundStyle(AppTheme.inkSoft.opacity(0.85))
            Text(value).font(.lora(12, weight: .semibold)).foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(AppTheme.parchmentCard))
        .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
    }
}
