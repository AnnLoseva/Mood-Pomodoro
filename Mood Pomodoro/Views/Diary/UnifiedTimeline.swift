import SwiftUI
import SwiftData
import Charts

/// One mark on the shared clock. Numeric points carry a 1–5 value; intervals
/// carry an end; events carry neither and are drawn as markers. Pills and
/// cycle never become marks — they have no exact time, so they live on the
/// day-context strip instead of a fake hour.
private struct TimelineMark: Identifiable {
    let id: String
    let date: Date
    var end: Date?
    let layer: TimelineLayer
    let title: String
    var value: Double?
    var color: Color = AppTheme.forest
    var target: DiaryEditTarget?
    /// Vertical slot inside the events lane, 0...1.
    var eventPosition: Double = 0.5
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
        case .context: return AppTheme.inkSoft
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

    static let numericLayers: [TimelineLayer] = [.mood, .energy, .motivation, .hunger, .appetite]
    static let defaultOn: Set<String> = ["mood", "sleep", "food"]
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

private struct LineSegment: Identifiable {
    let id: String
    let start: Date
    let startValue: Double
    let end: Date
    let endValue: Double
    let color: Color
}

/// Raw events on a shared clock. Period mode does not silently average
/// events: a month still shows every mark, and lines only join neighbours
/// within 90 minutes so sparse check-ins never look like a continuous line.
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

    @AppStorage("diary.timeline.layers") private var layersRaw = "mood,sleep,food"
    @State private var span: TimelineSpan
    @State private var selection: Date?
    @State private var visibleSpan: TimeInterval?
    @State private var scrollStart: Date?
    @State private var spanAtPinchStart: TimeInterval?

    private let calendar = Calendar.current
    private static let minimumSpan: TimeInterval = 15 * 60
    private static let yLabelWidth: CGFloat = 22
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
    }

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
                    color: foodColor(entry.category), target: .food(entry.id), eventPosition: 0.72
                ))
            }
        }
        if isOn(.emotion) {
            for entry in emotions where within(entry.eventDate) {
                for emotion in entry.emotions {
                    result.append(TimelineMark(
                        id: "\(entry.id)-\(emotion.rawValue)", date: entry.eventDate, layer: .emotion,
                        title: "\(emotion.emoji) \(emotion.label)",
                        color: emotion.color, target: .emotion(entry.id), eventPosition: 0.88
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
                    color: AppTheme.rust, target: .impulse(entry.id), eventPosition: 0.22
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

    private var numericSegments: [LineSegment] {
        TimelineLayer.numericLayers.filter(isOn).flatMap { layer in
            let pts = marks.filter { $0.layer == layer && $0.value != nil }
            return zip(pts, pts.dropFirst()).compactMap { a, b -> LineSegment? in
                guard let av = a.value, let bv = b.value else { return nil }
                guard b.date.timeIntervalSince(a.date) <= Self.connectGap else { return nil }
                return LineSegment(
                    id: "\(a.id)|\(b.id)",
                    start: a.date, startValue: av,
                    end: b.date, endValue: bv,
                    color: a.color
                )
            }
        }
    }

    private var fullSpan: TimeInterval { domain.upperBound.timeIntervalSince(domain.lowerBound) }
    private var visibleLength: TimeInterval { min(visibleSpan ?? fullSpan, fullSpan) }
    private var isZoomed: Bool { visibleLength < fullSpan - 1 }
    private var canZoom: Bool { fullSpan > Self.minimumSpan * 1.5 }

    private var scrollBinding: Binding<Date> {
        Binding(
            get: { scrollStart ?? domain.lowerBound },
            set: { scrollStart = $0 }
        )
    }

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

    var body: some View {
        DiaryCard(title: L("Общий график", "Timeline")) {
            VStack(alignment: .leading, spacing: 12) {
                spanPicker
                layerToggles
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
                    lanes
                    zoomControls
                    selectionDetails
                }
            }
        }
        .onChange(of: suggestedPeriod) { _, new in
            switch new {
            case .month: span = .month
            case .weekOfYear, .weekOfMonth: span = .week
            default: span = .day
            }
            visibleSpan = nil
            scrollStart = nil
            selection = nil
        }
        .onChange(of: date) { _, _ in
            visibleSpan = nil
            scrollStart = nil
            selection = nil
        }
        .onChange(of: span) { _, _ in
            visibleSpan = nil
            scrollStart = nil
            selection = nil
        }
    }

    private var enabledChartLayers: [TimelineLayer] {
        TimelineLayer.allCases.filter { $0 != .context && isOn($0) }
    }

    private var spanPicker: some View {
        HStack(spacing: 8) {
            ForEach(TimelineSpan.allCases) { item in
                let selected = item == span
                Button {
                    span = item
                } label: {
                    Text(item.title)
                        .font(.lora(12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppTheme.parchmentCard : AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? AppTheme.forest : AppTheme.parchment.opacity(0.5)))
                        .overlay(Capsule().stroke(AppTheme.border, lineWidth: selected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var layerToggles: some View {
        FlowLayout(spacing: 6) {
            ForEach(TimelineLayer.allCases) { layer in
                let on = isOn(layer)
                Button { toggle(layer) } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(on ? layer.color : AppTheme.border)
                            .frame(width: 7, height: 7)
                        Text(layer.title)
                            .font(.lora(12, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? AppTheme.ink : AppTheme.inkSoft)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(on ? layer.color.opacity(0.16) : AppTheme.parchment.opacity(0.4))
                    )
                    .overlay(
                        Capsule().stroke(on ? layer.color : AppTheme.border, lineWidth: on ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layer.title)
                .accessibilityValue(on ? L("показан", "shown") : L("скрыт", "hidden"))
            }
        }
    }

    @ViewBuilder
    private var lanes: some View {
        let numericOn = TimelineLayer.numericLayers.contains(where: isOn)
        let eventsOn = TimelineLayer.allCases.contains { $0.isEvent && isOn($0) }
        let showNumeric = numericOn && marks.contains { $0.layer.isNumeric }
        let showSleep = isOn(.sleep) && marks.contains { $0.layer == .sleep }
        let showActivity = isOn(.activity) && marks.contains { $0.layer == .activity }
        let showEvents = eventsOn && marks.contains { $0.layer.isEvent }
        let lastChart: TimelineLayer? = {
            if showEvents { return .emotion }
            if showActivity { return .activity }
            if showSleep { return .sleep }
            if showNumeric { return .mood }
            return nil
        }()

        VStack(alignment: .leading, spacing: 8) {
            if numericOn {
                if showNumeric {
                    laneLabel(L("Шкалы 1–5 · без усреднения", "1–5 scales · not averaged"))
                    numericLane(showXAxis: lastChart == .mood)
                } else {
                    emptyLane(L("Нет отметок на шкалах за этот период", "No scale marks in this period"))
                }
            }
            if isOn(.sleep) {
                if showSleep {
                    laneLabel(L("Сон · реальные часы", "Sleep · real hours"))
                    intervalLane(layer: .sleep, showXAxis: lastChart == .sleep)
                } else {
                    emptyLane(L("Сон за этот период не записан", "No sleep recorded in this period"))
                }
            }
            if isOn(.activity) {
                if showActivity {
                    laneLabel(L("Занятия", "Activities"))
                    intervalLane(layer: .activity, showXAxis: lastChart == .activity)
                    activityLegend
                } else {
                    emptyLane(L("Занятий за этот период нет", "No activities in this period"))
                }
            }
            if eventsOn {
                if showEvents {
                    laneLabel(L("События", "Events"))
                    eventLane(showXAxis: lastChart == .emotion)
                } else {
                    emptyLane(L("Событий на выбранных слоях нет", "No events on the chosen layers"))
                }
            }
            if isOn(.context) {
                contextStrip
            }
        }
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

    private func laneLabel(_ text: String) -> some View {
        Text(text)
            .font(.lora(11))
            .foregroundStyle(AppTheme.inkSoft)
    }

    private func emptyLane(_ text: String) -> some View {
        Text(text)
            .font(.lora(12))
            .foregroundStyle(AppTheme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private var numericPoints: [TimelineMark] { marks.filter { $0.layer.isNumeric && $0.value != nil } }

    private func numericLane(showXAxis: Bool) -> some View {
        Chart {
            ForEach(numericSegments) { segment in
                LineMark(
                    x: .value("Time", segment.start),
                    y: .value("Value", segment.startValue),
                    series: .value("Pair", segment.id)
                )
                .foregroundStyle(segment.color.opacity(0.7))
                LineMark(
                    x: .value("Time", segment.end),
                    y: .value("Value", segment.endValue),
                    series: .value("Pair", segment.id)
                )
                .foregroundStyle(segment.color.opacity(0.7))
            }
            ForEach(numericPoints) { point in
                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value ?? 0)
                )
                .foregroundStyle(point.color)
                .symbolSize(34)
            }
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(AppTheme.ink.opacity(0.35))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 1.0...5.0)
        .chartYAxis { numericYAxis }
        .modifier(TimelineXAxis(visible: showXAxis, span: span))
        .chartXSelection(value: $selection)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: scrollBinding)
        .chartLegend(.hidden)
        .frame(height: 160)
        .accessibilityLabel(L("Шкалы 1–5", "1–5 scales"))
    }

    private func intervalLane(layer: TimelineLayer, showXAxis: Bool) -> some View {
        let items = marks.filter { $0.layer == layer }
        return Chart {
            ForEach(items) { item in
                if let end = item.end {
                    RectangleMark(
                        xStart: .value("Start", max(item.date, interval.start)),
                        xEnd: .value("End", min(end, interval.end)),
                        yStart: .value("Bottom", 0.22),
                        yEnd: .value("Top", 0.78)
                    )
                    .foregroundStyle(item.color.opacity(0.85))
                    .cornerRadius(3)
                }
            }
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(AppTheme.ink.opacity(0.35))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0.0...1.0)
        .chartYAxis { spacerYAxis }
        .modifier(TimelineXAxis(visible: showXAxis, span: span))
        .chartXSelection(value: $selection)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: scrollBinding)
        .chartLegend(.hidden)
        .frame(height: 56)
        .accessibilityLabel(layer.title)
    }

    private func eventLane(showXAxis: Bool) -> some View {
        let items = marks.filter(\.layer.isEvent)
        return Chart {
            ForEach(items) { item in
                PointMark(
                    x: .value("Time", item.date),
                    y: .value("Event", item.eventPosition)
                )
                .foregroundStyle(item.color)
                .symbolSize(70)
            }
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(AppTheme.ink.opacity(0.35))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0.0...1.0)
        .chartYAxis { spacerYAxis }
        .modifier(TimelineXAxis(visible: showXAxis, span: span))
        .chartXSelection(value: $selection)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: scrollBinding)
        .chartLegend(.hidden)
        .frame(height: 70)
        .accessibilityLabel(L("События", "Events"))
    }

    @AxisContentBuilder
    private var numericYAxis: some AxisContent {
        AxisMarks(values: [1.0, 3.0, 5.0]) { value in
            AxisGridLine().foregroundStyle(AppTheme.border)
            AxisValueLabel {
                Text(value.as(Double.self).map { "\(Int($0))" } ?? "")
                    .font(.lora(10))
                    .foregroundStyle(AppTheme.inkSoft)
                    .frame(width: Self.yLabelWidth, alignment: .trailing)
            }
        }
    }

    @AxisContentBuilder
    private var spacerYAxis: some AxisContent {
        AxisMarks(values: [0.5]) { _ in
            AxisValueLabel {
                Text(" ").frame(width: Self.yLabelWidth)
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

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Контекст дня · без точного времени", "Day context · no exact time"))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
            if contextDays.isEmpty {
                Text(L("Нет дневных отметок за период", "No day-level marks in this period"))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(contextDays) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DateFormatting.compactDate(day.day))
                                    .font(.lora(11, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Button {
                                    onEdit(.support(day.day), day.day)
                                } label: {
                                    Text(day.support.map { "💊 \($0.glyph) \($0.label)" } ?? L("💊 Не отмечено", "💊 Not recorded"))
                                        .font(.lora(11))
                                        .foregroundStyle(AppTheme.ink)
                                }
                                .buttonStyle(.plain)
                                if day.isPeriodDay {
                                    Text(L("🔴 Менструация", "🔴 Period"))
                                        .font(.lora(11))
                                        .foregroundStyle(AppTheme.ink)
                                }
                                if let cycleDay = day.cycleDay {
                                    Text(L("День цикла \(cycleDay)", "Cycle day \(cycleDay)"))
                                        .font(.lora(11))
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppTheme.parchment.opacity(0.7))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectionDetails: some View {
        if let selection {
            let nearby = marks.sorted { distance($0, selection) < distance($1, selection) }.prefix(6)
            if nearby.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Рядом с отметкой", "Near this moment"))
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.inkSoft)
                    ForEach(Array(nearby)) { mark in
                        Button {
                            if let target = mark.target { onEdit(target, mark.date) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(mark.color).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mark.title)
                                        .font(.lora(13, weight: .medium))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(timeLine(mark))
                                        .font(.lora(11))
                                        .foregroundStyle(AppTheme.inkSoft)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Text(L("Нажми на график, чтобы увидеть запись и открыть её.", "Tap the chart to see a record and open it."))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }

    private func timeLine(_ mark: TimelineMark) -> String {
        let start = mark.date.formatted(date: span == .day ? .omitted : .abbreviated, time: .shortened)
        if let end = mark.end {
            return start + " – " + end.formatted(date: span == .day ? .omitted : .abbreviated, time: .shortened)
        }
        return start
    }

    private func distance(_ mark: TimelineMark, _ date: Date) -> Double {
        if let end = mark.end, date >= mark.date && date <= end { return 0 }
        return abs(mark.date.timeIntervalSince(date))
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
                    Button(L("Весь период", "Whole period")) {
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
}

/// Shared X-axis so stacked lanes line up. Hidden on every lane except the
/// last visible chart, so the clock is labelled once.
private struct TimelineXAxis: ViewModifier {
    let visible: Bool
    let span: TimelineSpan

    func body(content: Content) -> some View {
        if visible {
            content.chartXAxis {
                AxisMarks(values: .automatic(desiredCount: span == .day ? 4 : 6)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.border)
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(label(date))
                                .font(.lora(10))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
            }
        } else {
            content.chartXAxis(.hidden)
        }
    }

    private func label(_ date: Date) -> String {
        switch span {
        case .day: return DateFormatting.time(date)
        case .week, .month: return DateFormatting.compactDate(date)
        }
    }
}
