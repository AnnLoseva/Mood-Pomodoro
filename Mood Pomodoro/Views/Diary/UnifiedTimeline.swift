import SwiftUI
import SwiftData
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

/// One mark on the shared clock. Numeric points carry a 1–5 value; intervals
/// carry an end; events carry neither and are drawn as markers. Pills and
/// cycle never become marks — they have no exact time, so they live on the
/// context ribbon instead of a fake hour.
private struct TimelineMark: Identifiable {
    let id: String
    let date: Date
    var end: Date?
    let layer: TimelineLayer
    let title: String
    var value: Double?
    var color: Color = AppTheme.forest
    var target: DiaryEditTarget?
    /// Vertical slot inside the events lane, 0...1 (top to bottom).
    var eventPosition: Double = 0.5
    /// Art asset for the event marker (emotion/food), if any.
    var art: String?
}

private enum TimelineLayer: String, CaseIterable, Identifiable {
    case mood, energy, motivation, hunger, appetite
    case sleep, activity
    case emotion, food, impulse
    case context

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: return L("Настроение", "Mood")
        case .energy: return L("Энергия", "Energy")
        case .motivation: return L("Мотивация", "Motivation")
        case .hunger: return L("Голод", "Hunger")
        case .appetite: return L("Аппетит", "Appetite")
        case .sleep: return L("Сон", "Sleep")
        case .activity: return L("Занятия", "Activities")
        case .emotion: return L("Эмоции", "Emotions")
        case .food: return L("Еда", "Food")
        case .impulse: return L("Импульсы", "Impulses")
        case .context: return L("Таблетки и цикл", "Medication and cycle")
        }
    }

    var color: Color {
        switch self {
        case .mood: return DayScaleMetric.mood.color
        case .energy: return DayScaleMetric.energy.color
        case .motivation: return DayScaleMetric.motivation.color
        case .hunger: return DayScaleMetric.hunger.color
        case .appetite: return DayScaleMetric.appetite.color
        case .sleep: return Color(red: 0.32, green: 0.40, blue: 0.55)
        case .activity: return AppTheme.forest
        case .emotion: return Color(red: 0.494, green: 0.376, blue: 0.604)
        case .food: return AppTheme.moss
        case .impulse: return AppTheme.rust
        case .context: return Color(red: 0.541, green: 0.455, blue: 0.349)
        }
    }

    /// A darker shade of `color`, for text/labels that sit on a tinted chip
    /// or need to stay legible over the parchment background.
    var textColor: Color {
        switch self {
        case .mood: return AppTheme.forestDeep
        case .energy: return Color(red: 0.541, green: 0.416, blue: 0.031)
        case .motivation: return Color(red: 0.588, green: 0.161, blue: 0.122)
        case .hunger: return Color(red: 0.173, green: 0.396, blue: 0.380)
        case .appetite: return Color(red: 0.588, green: 0.282, blue: 0.165)
        case .sleep: return Color(red: 0.235, green: 0.298, blue: 0.431)
        case .activity: return AppTheme.forestDeep
        case .emotion: return Color(red: 0.373, green: 0.275, blue: 0.463)
        case .food: return Color(red: 0.353, green: 0.404, blue: 0.251)
        case .impulse: return AppTheme.rustDeep
        case .context: return Color(red: 0.420, green: 0.345, blue: 0.251)
        }
    }

    var isNumeric: Bool {
        switch self {
        case .mood, .energy, .motivation, .hunger, .appetite: return true
        default: return false
        }
    }

    var isInterval: Bool { self == .sleep || self == .activity }
    var isEvent: Bool { self == .emotion || self == .food || self == .impulse }

    /// Row inside the events lane, top to bottom — matches the new design's
    /// fixed rows (Эмоции / Еда / Импульсы).
    var eventRowFraction: Double {
        switch self {
        case .emotion: return 0.2
        case .food: return 0.5
        case .impulse: return 0.8
        default: return 0.5
        }
    }

    static let numericLayers: [TimelineLayer] = [.mood, .energy, .motivation, .hunger, .appetite]
    static let defaultOn: Set<String> = ["mood", "sleep", "food"]
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
        TimelinePreset(key: "food", title: L("Еда и голод", "Food & hunger"), layers: ["hunger", "appetite", "mood", "food", "impulse"]),
        TimelinePreset(key: "rest", title: L("Сон и силы", "Sleep & energy"), layers: ["energy", "mood", "sleep", "activity", "context"])
    ]
}

private enum TimelineSpan: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return L("День", "Day")
        case .week: return L("Неделя", "Week")
        case .month: return L("Месяц", "Month")
        }
    }
    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

/// Fixed pixel geometry for the unified plot, computed once per draw from
/// the canvas size and the currently visible time window. Shared by the
/// `Canvas` renderer and the SwiftUI overlays (tooltip/selection cards) so
/// they never drift apart.
private struct ChartLayout {
    let size: CGSize
    let win: ClosedRange<Date>
    let compact: Bool

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
    var bandTop: CGFloat { scaleBottom + bandGap }
    var bandBottom: CGFloat { bandTop + bandHeight }
    var ctxTop: CGFloat { bandBottom + ctxGap }
    var ctxBottom: CGFloat { ctxTop + ctxHeight }
    var tickY: CGFloat { ctxBottom + tickGap }
    var totalHeight: CGFloat { tickY + 26 }

    var scaleRect: CGRect { CGRect(x: x0, y: scaleTop, width: plotWidth, height: scaleHeight) }
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

    func eventY(_ layer: TimelineLayer) -> CGFloat {
        bandTop + CGFloat(layer.eventRowFraction) * bandHeight
    }
}

/// Raw events on a shared clock, drawn as one combined plot (scales, bands,
/// events, context) instead of stacked separate charts. Period mode does
/// not silently average events: a month still shows every mark, and lines
/// only join neighbours within 90 minutes so sparse check-ins never look
/// like a continuous line.
struct UnifiedTimeline: View {
    let date: Date
    let suggestedPeriod: Calendar.Component
    let onEdit: (DiaryEditTarget, Date) -> Void

    @Query private var checkIns: [CheckIn]
    @Query private var sessions: [FocusSession]
    @Query private var food: [FoodEntry]
    @Query private var hunger: [HungerEntry]
    @Query private var emotions: [EmotionEntry]
    @Query private var impulses: [ImpulseEntry]
    @Query private var support: [SupportEntry]
    @Query private var cycle: [CycleEntry]
    @Environment(SleepStore.self) private var sleep

    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("diary.timeline.layers") private var layersRaw = "mood,sleep,food"
    @AppStorage("diary.timeline.preset") private var presetKeyRaw = ""
    @State private var span: TimelineSpan
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
    private static let connectGap: TimeInterval = 90 * 60

    init(date: Date, period: Calendar.Component, onEdit: @escaping (DiaryEditTarget, Date) -> Void) {
        self.date = date
        self.suggestedPeriod = period
        self.onEdit = onEdit
        let initial: TimelineSpan
        switch period {
        case .month: initial = .month
        case .weekOfYear, .weekOfMonth: initial = .week
        default: initial = .day
        }
        _span = State(initialValue: initial)
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
        calendar.dateInterval(of: span.calendarComponent, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 3600)
    }

    private var domain: ClosedRange<Date> { interval.start...interval.end }

    private func overlaps(_ start: Date, _ end: Date) -> Bool {
        start < interval.end && end > interval.start
    }

    private func within(_ time: Date) -> Bool {
        time >= interval.start && time < interval.end
    }

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

    private func pan(_ direction: Double) {
        guard isZoomed else { return }
        let start = (scrollStart ?? domain.lowerBound).addingTimeInterval(direction * visibleLength * 0.3)
        let half = visibleLength
        let lowest = domain.lowerBound
        let highest = max(lowest, domain.upperBound.addingTimeInterval(-half))
        scrollStart = min(max(start, lowest), highest)
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

    // MARK: - Marks

    private var marks: [TimelineMark] {
        var result: [TimelineMark] = []
        for entry in checkIns where within(entry.timestamp) {
            if isOn(.mood) {
                result.append(TimelineMark(
                    id: "\(entry.id)-mood", date: entry.timestamp, layer: .mood,
                    title: DayMetric.mood.title + " · \(Int(entry.mood.scale))/5",
                    value: entry.mood.scale, color: DayMetric.mood.color, target: .checkIn(entry.id)
                ))
            }
            if isOn(.energy), let value = entry.energy?.scale {
                result.append(TimelineMark(
                    id: "\(entry.id)-energy", date: entry.timestamp, layer: .energy,
                    title: DayMetric.energy.title + " · \(Int(value))/5",
                    value: value, color: DayMetric.energy.color, target: .checkIn(entry.id)
                ))
            }
            if isOn(.motivation), let value = entry.motivation?.scale {
                result.append(TimelineMark(
                    id: "\(entry.id)-motivation", date: entry.timestamp, layer: .motivation,
                    title: DayMetric.motivation.title + " · \(Int(value))/5",
                    value: value, color: DayMetric.motivation.color, target: .checkIn(entry.id)
                ))
            }
        }
        for entry in hunger where within(entry.eventDate) {
            if isOn(.hunger), let value = entry.hunger?.scale {
                result.append(TimelineMark(
                    id: "h\(entry.id)", date: entry.eventDate, layer: .hunger,
                    title: L("Голод", "Hunger") + " · \(Int(value))/5",
                    value: value, color: DayScaleMetric.hunger.color, target: .hunger(entry.id)
                ))
            }
            if isOn(.appetite), let value = entry.appetite?.scale {
                result.append(TimelineMark(
                    id: "a\(entry.id)", date: entry.eventDate, layer: .appetite,
                    title: L("Аппетит", "Appetite") + " · \(Int(value))/5",
                    value: value, color: DayScaleMetric.appetite.color, target: .hunger(entry.id)
                ))
            }
        }
        if isOn(.food) {
            for entry in food where within(entry.eventDate) {
                result.append(TimelineMark(
                    id: "food-\(entry.id)", date: entry.eventDate, layer: .food,
                    title: "\(entry.category.emoji) \(entry.category.label)",
                    color: foodColor(entry.category), target: .food(entry.id),
                    eventPosition: TimelineLayer.food.eventRowFraction, art: entry.category.imageName
                ))
            }
        }
        if isOn(.emotion) {
            for entry in emotions where within(entry.eventDate) {
                for emotion in entry.emotions {
                    result.append(TimelineMark(
                        id: "\(entry.id)-\(emotion.rawValue)", date: entry.eventDate, layer: .emotion,
                        title: "\(emotion.emoji) \(emotion.label)",
                        color: emotion.color, target: .emotion(entry.id),
                        eventPosition: TimelineLayer.emotion.eventRowFraction, art: emotion.imageName
                    ))
                }
            }
        }
        if isOn(.impulse) {
            for entry in impulses where within(entry.eventDate) {
                let extra = entry.detailLine
                result.append(TimelineMark(
                    id: "imp-\(entry.id)", date: entry.eventDate, layer: .impulse,
                    title: extra.isEmpty
                        ? "\(entry.category.emoji) \(entry.category.label)"
                        : "\(entry.category.emoji) \(entry.category.label) · \(extra)",
                    color: AppTheme.rust, target: .impulse(entry.id), eventPosition: TimelineLayer.impulse.eventRowFraction
                ))
            }
        }
        if isOn(.sleep) {
            for entry in sleep.sessions where !entry.isSuperseded && overlaps(entry.start, entry.end) {
                result.append(TimelineMark(
                    id: "sleep-\(entry.id)", date: entry.start, end: entry.end, layer: .sleep,
                    title: entry.kind.emoji + " " + entry.kind.label + " · " + DurationFormatting.compact(entry.totalSleep)
                        + (entry.quality.map { " · " + $0.label } ?? ""),
                    color: entry.kind == .night
                        ? Color(red: 0.32, green: 0.40, blue: 0.55)
                        : Color(red: 0.55, green: 0.62, blue: 0.45),
                    target: .sleep(entry.id)
                ))
            }
        }
        if isOn(.activity) {
            for session in sessions {
                for segment in session.segments ?? [] where segment.type == .work && overlaps(segment.startDate, segment.endDate ?? .now) {
                    result.append(TimelineMark(
                        id: "seg-\(segment.id)", date: segment.startDate, end: segment.endDate ?? .now,
                        layer: .activity,
                        title: Ldata(session.activity) + " · " + SessionType.label(for: session.sessionType),
                        color: SessionType.color(for: session.sessionType),
                        target: .session(session.id)
                    ))
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    private func foodColor(_ category: FoodCategory) -> Color {
        switch category {
        case .healthy: return AppTheme.moss
        case .regular: return AppTheme.forest
        case .treat: return AppTheme.rust
        }
    }

    private var numericPoints: [TimelineMark] { marks.filter { $0.layer.isNumeric && $0.value != nil } }
    private var eventPoints: [TimelineMark] { marks.filter(\.layer.isEvent) }
    private var bandMarks: [TimelineMark] { marks.filter(\.layer.isInterval) }

    private func numericGroups(for layer: TimelineLayer) -> [[TimelineMark]] {
        let pts = numericPoints.filter { $0.layer == layer }.sorted { $0.date < $1.date }
        var out: [[TimelineMark]] = []
        var current: [TimelineMark] = []
        for (i, p) in pts.enumerated() {
            if i > 0, p.date.timeIntervalSince(pts[i - 1].date) > Self.connectGap {
                out.append(current)
                current = []
            }
            current.append(p)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private func valueAt(_ layer: TimelineLayer, _ time: Date, snap: Bool = false) -> Double? {
        let pts = numericPoints.filter { $0.layer == layer }.sorted { $0.date < $1.date }
        guard !pts.isEmpty else { return nil }
        for (a, b) in zip(pts, pts.dropFirst()) {
            let gap = b.date.timeIntervalSince(a.date)
            if time >= a.date && time <= b.date, gap > 0, gap <= Self.connectGap {
                let k = time.timeIntervalSince(a.date) / gap
                return (a.value ?? 0) + ((b.value ?? 0) - (a.value ?? 0)) * k
            }
        }
        if let only = pts.first, pts.count == 1, abs(only.date.timeIntervalSince(time)) < Self.connectGap / 2 {
            return only.value
        }
        guard snap else { return nil }
        let window: TimeInterval = span == .day ? 20 * 60 : 6 * 3600
        if let nearest = pts.min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
           abs(nearest.date.timeIntervalSince(time)) <= window {
            return nearest.value
        }
        return nil
    }

    private var contextDays: [DayAggregate] {
        AnalyticsService.dayAggregates(
            in: interval,
            checkIns: checkIns,
            sessions: sessions,
            hungerEntries: hunger,
            foodEntries: food,
            emotionEntries: emotions,
            impulseEntries: impulses,
            supportEntries: support,
            cycleMarks: cycle.map(\.mark) + sleep.cycleMarks,
            healthMedication: sleep.medicationDays,
            sleepSessions: sleep.sessions
        )
    }

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
        .onChange(of: suggestedPeriod) { _, new in
            switch new {
            case .month: span = .month
            case .weekOfYear, .weekOfMonth: span = .week
            default: span = .day
            }
            clearSelection()
        }
        .onChange(of: date) { _, _ in clearSelection() }
        .onChange(of: span) { _, _ in clearSelection() }
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
                    selectToggle
                }
            } else {
                HStack(spacing: 8) {
                    spanPicker
                    if canZoom { navCluster }
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
                    span = item
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
                .disabled(!isZoomed || isSelecting)
            navButton("minus", label: L("Отдалить", "Zoom out")) { zoomBy(1.55) }
                .disabled(!isZoomed || isSelecting)
            navButton("plus", label: L("Приблизить", "Zoom in")) { zoomBy(0.65) }
                .disabled(isSelecting)
            navButton("chevron.right", label: L("Вперёд", "Forward")) { pan(1) }
                .disabled(!isZoomed || isSelecting)
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
                let layout = ChartLayout(size: proxy.size, win: win, compact: isCompact)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(context: &context, layout: layout)
                    }
                    .frame(width: proxy.size.width, height: layout.totalHeight)

                    TimelineChartGestures(
                        mode: isSelecting ? .select : .browse,
                        panEnabled: isSelecting || isZoomed,
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
                                panAnchor = nil
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
            .frame(height: ChartLayout(size: .zero, win: win, compact: isCompact).totalHeight)
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
        if layout.bandRect.insetBy(dx: -10, dy: -10).contains(point) {
            var best: (TimelineMark, CGFloat)?
            for mark in eventPoints {
                let p = CGPoint(x: layout.x(mark.date), y: layout.eventY(mark.layer))
                let d = hypot(p.x - point.x, p.y - point.y)
                if d < 22, best == nil || d < best!.1 { best = (mark, d) }
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
            for mark in eventPoints {
                let p = CGPoint(x: layout.x(mark.date), y: layout.eventY(mark.layer))
                if let art = mark.art {
                    ctx.draw(Image(art), in: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24))
                } else {
                    let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                    ctx.fill(dot, with: .color(mark.color))
                    ctx.stroke(dot, with: .color(AppTheme.parchmentCard), lineWidth: 1.6)
                }
            }
        }

        // Numeric scale lines + points, clipped to the scale zone.
        // Overlapping stretches become a candy-stripe dash of the colours
        // that share that path, so one series never hides another.
        context.drawLayer { ctx in
            ctx.clip(to: Path(layout.scaleRect))
            let activeScales = TimelineLayer.numericLayers.filter(isOn)
            let overlaps = overlapRuns(layout: layout, layers: activeScales)
            for layer in activeScales {
                for group in numericGroups(for: layer) where group.count > 1 {
                    let points = group.map { CGPoint(x: layout.x($0.date), y: layout.y($0.value ?? 0)) }
                    let path = smoothPath(points)
                    ctx.stroke(path, with: .color(AppTheme.parchmentCard), lineWidth: 6.4)
                    for range in soloRanges(for: layer, overlaps: overlaps, layout: layout) {
                        ctx.drawLayer { inner in
                            inner.clip(to: Path(CGRect(x: range.0, y: layout.scaleTop, width: range.1 - range.0, height: layout.scaleHeight)))
                            inner.stroke(path, with: .color(layer.color), lineWidth: 3)
                        }
                    }
                }
            }
            for run in overlaps where run.points.count > 1 {
                var path = Path()
                path.move(to: run.points[0])
                for point in run.points.dropFirst() { path.addLine(to: point) }
                ctx.stroke(path, with: .color(AppTheme.parchmentCard), lineWidth: 6.4)
                strokeCandyStripe(&ctx, path: path, colors: run.layers.map(\.color), lineWidth: 3.2)
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

    private struct StripeRun {
        var x0: CGFloat
        var x1: CGFloat
        var layers: [TimelineLayer]
        var points: [CGPoint]
    }

    /// Consecutive stretches where two or more numeric series share the same
    /// y (within a few pixels). Drawn as a candy-stripe of those colours so
    /// the lower line is never painted over and lost.
    private func overlapRuns(layout: ChartLayout, layers: [TimelineLayer]) -> [StripeRun] {
        guard layers.count >= 2 else { return [] }
        let step: CGFloat = 3
        let threshold: CGFloat = 7
        let minWidth: CGFloat = 8

        struct Sample {
            let x: CGFloat
            let clusters: [[TimelineLayer]]
            let yForLayer: [TimelineLayer: CGFloat]
        }

        var samples: [Sample] = []
        var x = layout.x0
        while x <= layout.x1 {
            let time = layout.date(atX: x)
            var yMap: [TimelineLayer: CGFloat] = [:]
            var remaining: [(TimelineLayer, CGFloat)] = []
            for layer in layers {
                if let value = valueAt(layer, time) {
                    let y = layout.y(value)
                    yMap[layer] = y
                    remaining.append((layer, y))
                }
            }
            remaining.sort { $0.1 < $1.1 }
            var clusters: [[TimelineLayer]] = []
            while !remaining.isEmpty {
                var cluster = [remaining.removeFirst()]
                var grew = true
                while grew {
                    grew = false
                    remaining.removeAll { item in
                        if cluster.contains(where: { abs($0.1 - item.1) <= threshold }) {
                            cluster.append(item)
                            grew = true
                            return true
                        }
                        return false
                    }
                }
                if cluster.count >= 2 {
                    let ordered = TimelineLayer.numericLayers.filter { layer in cluster.contains { $0.0 == layer } }
                    clusters.append(ordered)
                }
            }
            samples.append(Sample(x: x, clusters: clusters, yForLayer: yMap))
            x += step
        }

        func key(_ layers: [TimelineLayer]) -> String {
            layers.map(\.rawValue).joined(separator: ",")
        }

        var open: [String: StripeRun] = [:]
        var runs: [StripeRun] = []
        for sample in samples {
            let current = Set(sample.clusters.map(key))
            for (k, run) in open where !current.contains(k) {
                if run.x1 - run.x0 >= minWidth { runs.append(run) }
                open.removeValue(forKey: k)
            }
            for cluster in sample.clusters {
                let k = key(cluster)
                let ys = cluster.compactMap { sample.yForLayer[$0] }
                guard !ys.isEmpty else { continue }
                let point = CGPoint(x: sample.x, y: ys.reduce(0, +) / CGFloat(ys.count))
                if var run = open[k] {
                    run.x1 = sample.x
                    run.points.append(point)
                    open[k] = run
                } else {
                    open[k] = StripeRun(x0: sample.x, x1: sample.x, layers: cluster, points: [point])
                }
            }
        }
        for run in open.values where run.x1 - run.x0 >= minWidth {
            runs.append(run)
        }
        return runs
    }

    private func soloRanges(for layer: TimelineLayer, overlaps: [StripeRun], layout: ChartLayout) -> [(CGFloat, CGFloat)] {
        let involved = overlaps.filter { $0.layers.contains(layer) }.sorted { $0.x0 < $1.x0 }
        var ranges: [(CGFloat, CGFloat)] = []
        var cursorX = layout.x0
        for run in involved {
            if run.x0 > cursorX + 1 { ranges.append((cursorX, run.x0)) }
            cursorX = max(cursorX, run.x1)
        }
        if layout.x1 > cursorX + 1 { ranges.append((cursorX, layout.x1)) }
        return ranges
    }

    private func strokeCandyStripe(_ context: inout GraphicsContext, path: Path, colors: [Color], lineWidth: CGFloat) {
        let dash: CGFloat = 7
        let count = max(colors.count, 1)
        let gap = dash * CGFloat(count - 1)
        for (index, color) in colors.enumerated() {
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round, dash: [dash, gap], dashPhase: dash * CGFloat(index))
            )
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
            if let mark {
                Divider().overlay(ChartPalette.dashLine)
                Text(mark.title)
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
        return span == .week ? L("Неделя целиком", "Whole week") : L("Месяц целиком", "Whole month")
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
        let pts = numericPoints.filter { $0.layer == layer && $0.date >= range.lowerBound && $0.date <= range.upperBound }
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
        if isOn(.sleep) {
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
