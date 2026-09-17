import SwiftUI
import Charts

struct OverviewAnalyticsView: View {
    let snapshot: AnalyticsSnapshot
    @Environment(AppTabs.self) private var tabs
    @AppStorage("analytics.overview.series") private var seriesRaw = "mood,sleep"
    @AppStorage("analytics.overview.markers") private var markersRaw = "period"
    @State private var selectedDay: AnalyticsDayRow?

    private var series: Set<String> {
        Set(seriesRaw.split(separator: ",").map(String.init))
    }

    private var markers: Set<String> {
        Set(markersRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                summaryCard
                chartCard
                if !snapshot.overview.deltas.isEmpty { deltasCard }
                cardsGrid
                if !snapshot.trajectory.isEmpty { trajectoryCard }
                reasonsCard
                insightsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .sheet(item: $selectedDay) { day in
            daySheet(day)
        }
    }

    private var summaryCard: some View {
        let o = snapshot.overview
        return VStack(alignment: .leading, spacing: 12) {
            Text(o.periodLabel)
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
            HStack {
                AnalyticsStatTile(title: L("Дней с данными", "Days with data"), value: "\(o.daysWithData)/\(o.dayCount)")
                AnalyticsStatTile(title: L("Заполненность", "Coverage"), value: "\(Int((o.coverage * 100).rounded()))%")
            }
            HStack {
                AnalyticsStatTile(title: L("Настроение", "Mood"), value: analyticsFormat(o.mood.average))
                AnalyticsStatTile(title: L("Энергия", "Energy"), value: analyticsFormat(o.energy.average))
                AnalyticsStatTile(title: L("Мотивация", "Motivation"), value: analyticsFormat(o.motivation.average))
            }
            AnalyticsReliabilityBadge(confidence: o.mood.confidence, extra: L("\(o.mood.dayCount) дн. · \(o.checkInCount) отметок", "\(o.mood.dayCount) days · \(o.checkInCount) check-ins"))
        }
        .padding(18)
        .parchmentCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L(
            "Обзор периода \(o.periodLabel). Настроение \(analyticsFormat(o.mood.average)), энергия \(analyticsFormat(o.energy.average)), мотивация \(analyticsFormat(o.motivation.average))",
            "Period overview \(o.periodLabel). Mood \(analyticsFormat(o.mood.average)), energy \(analyticsFormat(o.energy.average)), motivation \(analyticsFormat(o.motivation.average))"
        ))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Общий график состояния", "Overall state chart"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            FlowLayout(spacing: 6) {
                ForEach(chartKeys, id: \.key) { item in
                    let on = series.contains(item.key)
                    Button { toggle(item.key) } label: {
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(item.title)
                        }
                        .font(.lora(11, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? AppTheme.parchmentCard : AppTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(on ? AppTheme.forest : AppTheme.chipFill))
                    }
                    .buttonStyle(.plain)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(markerKeys, id: \.key) { item in
                    let on = markers.contains(item.key)
                    Button { toggleMarker(item.key) } label: {
                        Text("\(item.symbol) \(item.title)")
                            .font(.lora(11, weight: on ? .semibold : .regular))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().stroke(on ? AppTheme.forest : AppTheme.border, lineWidth: 1).background(Capsule().fill(AppTheme.chipFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if snapshot.days.isEmpty {
                Text(L("Нет дней с данными в этом периоде.", "No days with data in this period."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                OverviewStateChart(
                    days: snapshot.days,
                    series: series,
                    markers: markers,
                    chartKeys: chartKeys,
                    onSelectDay: { selectedDay = $0 }
                )
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var chartKeys: [(key: String, title: String, color: Color)] {
        [
            ("mood", L("Настроение", "Mood"), AppTheme.forest),
            ("energy", L("Энергия", "Energy"), Color(red: 0.541, green: 0.416, blue: 0.031)),
            ("motivation", L("Мотивация", "Motivation"), Color(red: 0.588, green: 0.161, blue: 0.122)),
            ("sleep", L("Сон, ч", "Sleep, h"), Color(red: 0.32, green: 0.40, blue: 0.55)),
            ("appetite", L("Аппетит", "Appetite"), Color(red: 0.588, green: 0.282, blue: 0.165)),
            ("hunger", L("Сытость", "Satiety"), Color(red: 0.173, green: 0.396, blue: 0.380)),
            ("rest", L("Отдых, ч", "Rest, h"), AppTheme.moss),
            ("work", L("Работа, ч", "Work, h"), Color(red: 0.357, green: 0.463, blue: 0.541)),
            ("study", L("Учёба, ч", "Study, h"), Color(red: 0.769, green: 0.584, blue: 0.259))
        ]
    }

    private var markerKeys: [(key: String, title: String, symbol: String)] {
        [
            ("period", L("Менструация", "Period"), "●"),
            ("meds", L("Препараты", "Medication"), "✕"),
            ("impulse", L("Импульсы", "Impulses"), "◆"),
            ("food", L("Еда", "Food"), "■"),
            ("nap", L("Дневной сон", "Nap"), "▲")
        ]
    }

    private func toggle(_ key: String) {
        var set = series
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        if set.isEmpty { set.insert("mood") }
        seriesRaw = set.sorted().joined(separator: ",")
    }

    private func toggleMarker(_ key: String) {
        var set = markers
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        markersRaw = set.sorted().joined(separator: ",")
    }

    private var deltasCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Что изменилось", "What changed"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            ForEach(snapshot.overview.deltas, id: \.key) { delta in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(delta.title): \(String(format: "%+.1f", delta.difference))")
                        .font(.lora(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Text(L("\(delta.currentDays) дн. сейчас · \(delta.previousDays) дн. раньше · \(delta.confidence.shortLabel). Связь может зависеть от других факторов.", "\(delta.currentDays) days now · \(delta.previousDays) days before · \(delta.confidence.shortLabel). The link may depend on other factors."))
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var cardsGrid: some View {
        let o = snapshot.overview
        return VStack(spacing: 10) {
            compact(L("Сон", "Sleep"), analyticsDuration(o.averageSleepSeconds), L("\(o.nightCount) ночей", "\(o.nightCount) nights"))
            compact(L("Отдых", "Rest"), analyticsDuration(o.restSeconds), nil)
            compact(L("Обязательная работа", "Obligatory work"), analyticsDuration(o.workSeconds), nil)
            compact(L("Учёба", "Study"), analyticsDuration(o.studySeconds), nil)
            compact(L("Эмоции", "Emotions"), "\(o.emotionDayCount)", L("дней с отметками", "days with marks"))
            compact(L("Питание", "Food"), "\(o.mealCount)", analyticsFormat(o.appetite.average))
            compact(L("Импульсивность", "Impulsivity"), "\(o.impulseDayCount)", L("дней с отметками", "days with marks"))
            compact(L("Цикл", "Cycle"), "\(o.periodDayCount)", L("дней менструации", "period days"))
            compact(L("Препараты", "Medication"), "\(o.supportTakenDays)", L("не принято: \(o.supportSkippedDays)", "not taken: \(o.supportSkippedDays)"))
        }
    }

    private func compact(_ title: String, _ value: String, _ subtitle: String?) -> some View {
        HStack {
            Text(title).font(.lora(14)).foregroundStyle(AppTheme.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                if let subtitle {
                    Text(subtitle).font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
        .padding(14)
        .parchmentCard(padding: 0)
    }

    private var trajectoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Траектория сеанса", "Session trajectory"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Chart(snapshot.trajectory) { point in
                LineMark(x: .value("m", point.minuteBucketStart), y: .value("mood", point.averageMood))
                    .interpolationMethod(.linear)
                    .foregroundStyle(AppTheme.forest)
                PointMark(x: .value("m", point.minuteBucketStart), y: .value("mood", point.averageMood))
                    .foregroundStyle(AppTheme.forest)
                    .symbolSize(24)
            }
            .chartYScale(domain: 1...5)
            .frame(height: 140)
            .accessibilityLabel(L("Среднее настроение по минутам сеанса", "Average mood by session minute"))
            if let note = snapshot.declineNote {
                Text(note).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            } else {
                Text(L("Каждая точка — среднее независимых сеансов, не сырых отметок. Число сеансов подписано в данных точки.", "Each point is the mean of independent sessions, not raw check-ins. The session count lives on the point."))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var reasonsCard: some View {
        let rows = snapshot.reasons.prefix(6)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Частые причины", "Common reasons"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            if rows.isEmpty {
                Text(L("Пока мало заполненных причин.", "Too few filled-in reasons yet."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(Array(rows)) { row in
                    HStack {
                        Text(Ldata(row.reason)).font(.lora(14)).foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(row.count)/\(row.answeredTotal) · \(Int((row.percentageOfAnswered * 100).rounded()))%")
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    Text(L("из \(row.moodTotal) отметок этого настроения", "of \(row.moodTotal) check-ins at this mood"))
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var insightsCard: some View {
        let positive = snapshot.factors.filter { ($0.moodDelta ?? 0) > 0 && $0.confidence != .insufficient }.prefix(3)
        let negative = snapshot.factors.filter { ($0.moodDelta ?? 0) < 0 && $0.confidence != .insufficient }.prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("Что связано с состоянием", "What goes with mood"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("Положительные связи", "Positive links"))
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
            if positive.isEmpty {
                Text(L("Пока нет положительных связей с достаточным числом дней.", "No positive links with enough days yet."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(Array(positive)) { row in
                    factorLine(row)
                }
            }
            Text(L("Отрицательные связи", "Negative links"))
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
            if negative.isEmpty {
                Text(L("Пока нет отрицательных связей с достаточным числом дней.", "No negative links with enough days yet."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(Array(negative)) { row in
                    factorLine(row)
                }
            }
            Text(L("В дни с X среднее настроение было другим. Это наблюдение, не причина.", "On days with X, average mood was different. This is an observation, not a cause."))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(18)
        .parchmentCard()
    }

    private func factorLine(_ row: AnalyticsFactorRow) -> some View {
        HStack {
            Text(Ldata(row.optionName)).font(.lora(14)).foregroundStyle(AppTheme.ink)
            Spacer()
            Text(String(format: "%+.1f", row.moodDelta ?? 0))
                .font(.lora(14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            AnalyticsReliabilityBadge(confidence: row.confidence, extra: L("\(row.dayCount) дн.", "\(row.dayCount) days"))
        }
    }

    private func daySheet(_ day: AnalyticsDayRow) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(day.day.formatted(date: .abbreviated, time: .omitted))
                    .font(.lora(18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(L("Настроение \(analyticsFormat(day.mood)) · энергия \(analyticsFormat(day.energy)) · мотивация \(analyticsFormat(day.motivation))", "Mood \(analyticsFormat(day.mood)) · energy \(analyticsFormat(day.energy)) · motivation \(analyticsFormat(day.motivation))"))
                    .font(.lora(14))
                    .foregroundStyle(AppTheme.ink)
                Text(L("Сон \(analyticsDuration(day.sleepSeconds)) · еда \(day.mealCount) · импульсы \(day.impulseCount)", "Sleep \(analyticsDuration(day.sleepSeconds)) · meals \(day.mealCount) · impulses \(day.impulseCount)"))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                if day.supportRaw == SupportStatus.notTaken.rawValue {
                    Text(L("Препараты: не принято", "Medication: not taken")).font(.lora(13)).foregroundStyle(AppTheme.ink)
                } else if day.supportRaw == nil {
                    Text(L("Препараты: не отмечено", "Medication: not recorded")).font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                }
                Button(L("Открыть день в дневнике", "Open this day in the diary")) {
                    selectedDay = nil
                    tabs.openDiary(day: day.day)
                }
                .buttonStyle(.goblinSecondary)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.parchmentCard)
        }
        .presentationDetents([.medium])
        .goblinChrome()
    }
}

/// One drawn point of a toggled series (mood, energy, satiety, ...).
/// `hunger` is displayed inverted (`6 - value`) so the line reads as
/// satiety, growing with fullness rather than with hunger.
private struct OverviewSeriesPoint: Identifiable {
    let id: String
    let day: Date
    let title: String
    let color: Color
    let value: Double
}

private struct OverviewMarkerPoint: Identifiable {
    let id: String
    let day: Date
    let y: Double
    let color: Color
    let symbol: BasicChartSymbolShape
    let size: CGFloat
}

/// Isolated from the rest of the analytics page so dragging the crosshair
/// (`chartXSelection`) only re-renders this small view, not the whole
/// scroll of cards above and below it. The marks themselves are built once
/// per data/series change (stored `let`s), not on every drag frame.
private struct OverviewStateChart: View {
    let days: [AnalyticsDayRow]
    let series: Set<String>
    let markers: Set<String>
    let chartKeys: [(key: String, title: String, color: Color)]
    let onSelectDay: (AnalyticsDayRow) -> Void

    @State private var chartDate: Date?

    private let seriesPoints: [OverviewSeriesPoint]
    private let markerPoints: [OverviewMarkerPoint]
    private let dayByDate: [Date: AnalyticsDayRow]

    init(
        days: [AnalyticsDayRow],
        series: Set<String>,
        markers: Set<String>,
        chartKeys: [(key: String, title: String, color: Color)],
        onSelectDay: @escaping (AnalyticsDayRow) -> Void
    ) {
        self.days = days
        self.series = series
        self.markers = markers
        self.chartKeys = chartKeys
        self.onSelectDay = onSelectDay

        var points: [OverviewSeriesPoint] = []
        let activeKeys = chartKeys.filter { series.contains($0.key) }
        for item in activeKeys {
            for day in days {
                guard let raw = day.value(item.key) else { continue }
                let value = item.key == "hunger" ? 6 - raw : raw
                points.append(OverviewSeriesPoint(id: "\(item.key)|\(day.day)", day: day.day, title: item.title, color: item.color, value: value))
            }
        }
        self.seriesPoints = points

        var marks: [OverviewMarkerPoint] = []
        for day in days {
            if markers.contains("period"), day.isPeriodDay {
                marks.append(OverviewMarkerPoint(id: "period|\(day.day)", day: day.day, y: 0.35, color: .red, symbol: .circle, size: 36))
            }
            if markers.contains("meds") {
                if day.supportRaw == SupportStatus.notTaken.rawValue {
                    marks.append(OverviewMarkerPoint(id: "medsSkip|\(day.day)", day: day.day, y: 0.55, color: AppTheme.ink, symbol: .cross, size: 40))
                } else if day.supportRaw == SupportStatus.taken.rawValue {
                    marks.append(OverviewMarkerPoint(id: "medsTaken|\(day.day)", day: day.day, y: 0.55, color: AppTheme.forest, symbol: .circle, size: 24))
                }
            }
            if markers.contains("impulse"), day.impulseCount > 0 {
                marks.append(OverviewMarkerPoint(id: "impulse|\(day.day)", day: day.day, y: 0.75, color: AppTheme.rust, symbol: .diamond, size: 28))
            }
            if markers.contains("food"), day.hasFood {
                marks.append(OverviewMarkerPoint(id: "food|\(day.day)", day: day.day, y: 0.95, color: AppTheme.moss, symbol: .square, size: 22))
            }
            if markers.contains("nap"), day.hasNap {
                marks.append(OverviewMarkerPoint(id: "nap|\(day.day)", day: day.day, y: 1.15, color: Color(red: 0.32, green: 0.40, blue: 0.55), symbol: .triangle, size: 24))
            }
        }
        self.markerPoints = marks

        var byDate: [Date: AnalyticsDayRow] = [:]
        let calendar = Calendar.current
        for day in days {
            byDate[calendar.startOfDay(for: day.day)] = day
        }
        self.dayByDate = byDate
    }

    var body: some View {
        Chart {
            ForEach(seriesPoints) { point in
                LineMark(
                    x: .value(L("День", "Day"), point.day),
                    y: .value(point.title, point.value)
                )
                .foregroundStyle(point.color)
                .interpolationMethod(.linear)
                PointMark(
                    x: .value(L("День", "Day"), point.day),
                    y: .value(point.title, point.value)
                )
                .foregroundStyle(point.color)
                .symbolSize(20)
            }
            ForEach(markerPoints) { mark in
                PointMark(x: .value(L("День", "Day"), mark.day), y: .value("m", mark.y))
                    .foregroundStyle(mark.color)
                    .symbol(mark.symbol)
                    .symbolSize(mark.size)
            }
        }
        .chartYScale(domain: 0...12)
        .chartXSelection(value: $chartDate)
        .frame(height: 220)
        .accessibilityLabel(L("График состояния по дням. Настроение и сон включены по умолчанию.", "Daily state chart. Mood and sleep are on by default."))
        .onChange(of: chartDate) { _, date in
            guard let date else { return }
            if let row = dayByDate[Calendar.current.startOfDay(for: date)] {
                onSelectDay(row)
            }
        }
    }
}

extension AnalyticsDayRow: Hashable {
    static func == (lhs: AnalyticsDayRow, rhs: AnalyticsDayRow) -> Bool { lhs.day == rhs.day }
    func hash(into hasher: inout Hasher) { hasher.combine(day) }
}
