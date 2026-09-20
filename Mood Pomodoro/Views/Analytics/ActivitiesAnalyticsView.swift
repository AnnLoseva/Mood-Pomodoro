import SwiftUI
import Charts

/// Занятия: total active time, a chart of it by day, and the activities by
/// name. Each activity leads to its sessions — the old История, one step in.
struct ActivitiesAnalyticsView: View {
    @Bindable var store: AnalyticsStore
    @State private var sort = Sort.duration
    @State private var showAll = false

    fileprivate enum Sort: String, CaseIterable, Identifiable {
        case duration, sessions, mood, delta
        var id: String { rawValue }
        var title: String {
            switch self {
            case .duration: return L("По времени", "By time")
            case .sessions: return L("По числу сессий", "By sessions")
            case .mood: return L("По настроению", "By mood")
            case .delta: return L("По изменению", "By change")
            }
        }
    }

    private static let collapsedCount = 8

    var body: some View {
        let snapshot = store.snapshot
        let o = snapshot.overview
        let series = AnalyticsChartSeries.make(metric: .activity, days: snapshot.days)
        let rows = sorted(snapshot.activities)
        let visible = showAll ? rows : Array(rows.prefix(Self.collapsedCount))

        AnalyticsDetailScaffold(title: AnalyticsSection.activities.title, store: store) {
            if o.sessionCount == 0 {
                AnalyticsEmptyCard(
                    title: L("Нет сессий в периоде", "No sessions in this period"),
                    message: L("Начни сессию на вкладке «Сейчас» или добавь занятие в Дневнике.", "Start a session on Now or add an activity in the Diary.")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        AnalyticsStatTile(
                            title: L("Активное время", "Active time"),
                            value: analyticsDuration(o.restSeconds + o.workSeconds + o.studySeconds + o.untypedSeconds)
                        )
                        AnalyticsStatTile(title: L("Сессий", "Sessions"), value: "\(o.sessionCount)")
                        AnalyticsInfoButton(text: AnalyticsMetric.activity.methodNote)
                    }
                    AnalyticsMetricChart(series: [series], interval: snapshot.interval, height: 180)
                }
                .padding(16)
                .parchmentCard(padding: 0)

                AnalyticsDisclosure(L("По типам", "By type")) {
                    VStack(alignment: .leading, spacing: 8) {
                        typeRow(.rest, o.restSeconds)
                        typeRow(.obligatoryWork, o.workSeconds)
                        typeRow(.study, o.studySeconds)
                        if o.untypedSeconds > 0 {
                            HStack {
                                Text(SessionType.unassignedLabel).font(.lora(14)).foregroundStyle(AppTheme.ink)
                                Spacer(minLength: 8)
                                Text(analyticsDuration(o.untypedSeconds)).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("По названиям", "By name"))
                            .font(.lora(15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(Sort.allCases) { item in
                                Button { sort = item } label: {
                                    if item == sort { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(sort.title).font(.lora(13))
                                Image(systemName: "arrow.up.arrow.down").font(.system(size: 11))
                            }
                            .foregroundStyle(AppTheme.forestDeep)
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel(L("Порядок", "Order"))
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(AppTheme.border) }
                        NavigationLink(value: AnalyticsRoute.activity(canonicalData(row.name))) {
                            HStack(spacing: 10) {
                                Circle().fill(SessionType.color(for: row.typeRaw.flatMap(SessionType.init(rawValue:)))).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Ldata(row.name)).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                    Text(sessionsLine(row)).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                }
                                Spacer(minLength: 8)
                                Text(analyticsDuration(row.totalSeconds)).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.inkSoft)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if rows.count > Self.collapsedCount {
                        Button(showAll ? L("Свернуть", "Show fewer") : L("Показать все \(rows.count)", "Show all \(rows.count)")) {
                            showAll.toggle()
                        }
                        .buttonStyle(AnalyticsSmallButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .parchmentCard(padding: 0)

                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(
                        title: L("Все сессии", "All sessions"),
                        subtitle: L("каждая — со своими подробностями", "each with its own details"),
                        value: "\(o.sessionCount)",
                        route: .sessions(activity: nil)
                    )
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)

                if !snapshot.trajectory.isEmpty {
                    AnalyticsDisclosure(L("Траектория сеанса", "Session trajectory")) {
                        trajectory(snapshot)
                    }
                }
            }
        }
    }

    private func typeRow(_ type: SessionType, _ seconds: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Circle().fill(type.color).frame(width: 9, height: 9)
            Text(type.label).font(.lora(14)).foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            Text(analyticsDuration(seconds)).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
        }
    }

    private func sessionsLine(_ row: AnalyticsActivityRow) -> String {
        countLabel(row.sessionCount, ru: ("сессия", "сессии", "сессий"), en: ("session", "sessions"))
            + " · " + SessionType.label(for: row.typeRaw.flatMap(SessionType.init(rawValue:)))
    }

    private func sorted(_ rows: [AnalyticsActivityRow]) -> [AnalyticsActivityRow] {
        switch sort {
        case .duration: return rows.sorted { $0.totalSeconds > $1.totalSeconds }
        case .sessions: return rows.sorted { $0.sessionCount > $1.sessionCount }
        case .mood: return rows.sorted { ($0.mood.average ?? 0) > ($1.mood.average ?? 0) }
        case .delta: return rows.sorted { ($0.moodDelta ?? 0) > ($1.moodDelta ?? 0) }
        }
    }

    private func trajectory(_ snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(snapshot.trajectory) { point in
                LineMark(x: .value("m", point.minuteBucketStart), y: .value("mood", point.averageMood))
                    .interpolationMethod(.linear)
                    .foregroundStyle(AnalyticsMetric.mood.color)
                PointMark(x: .value("m", point.minuteBucketStart), y: .value("mood", point.averageMood))
                    .foregroundStyle(AnalyticsMetric.mood.color)
                    .symbol(AnalyticsMetric.mood.shape.chartSymbol)
                    .symbolSize(30)
            }
            .chartYScale(domain: 1...5)
            .frame(height: 140)
            .accessibilityLabel(L("Среднее настроение по минутам сессии", "Average mood by session minute"))
            Text(snapshot.declineNote ?? L("Каждая точка — среднее независимых сессий, не сырых отметок.", "Each point is the mean of independent sessions, not raw check-ins."))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
    }
}

/// One activity by name over the chosen period: its time, its sessions, and
/// how mood looked before, during and after.
struct ActivityDetailView: View {
    let name: String
    @Bindable var store: AnalyticsStore

    var body: some View {
        let snapshot = store.snapshot
        let rows = snapshot.activities.filter { canonicalData($0.name) == name }
        let total = rows.reduce(0) { $0 + $1.totalSeconds }
        let count = rows.reduce(0) { $0 + $1.sessionCount }
        AnalyticsDetailScaffold(title: Ldata(name), store: store) {
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    AnalyticsQuietNote(text: L("В этом периоде такого занятия нет.", "No such activity in this period."))
                    Button(L("Показать за всё время", "Show all time")) { store.period.kind = .all }
                        .buttonStyle(AnalyticsSmallButtonStyle())
                }
                .padding(16)
                .parchmentCard(padding: 0)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        AnalyticsStatTile(title: L("Всего", "Total"), value: analyticsDuration(total))
                        AnalyticsStatTile(title: L("Сессий", "Sessions"), value: "\(count)")
                        AnalyticsStatTile(title: L("В среднем", "Average"), value: analyticsDuration(count > 0 ? total / Double(count) : nil))
                    }
                    if rows.count > 1 {
                        ForEach(rows) { row in
                            HStack(spacing: 8) {
                                Circle().fill(SessionType.color(for: row.typeRaw.flatMap(SessionType.init(rawValue:)))).frame(width: 9, height: 9)
                                Text(SessionType.label(for: row.typeRaw.flatMap(SessionType.init(rawValue:))))
                                    .font(.lora(13)).foregroundStyle(AppTheme.ink)
                                Spacer(minLength: 8)
                                Text(analyticsDuration(row.totalSeconds)).font(.lora(13, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            }
                        }
                    } else if let type = rows.first?.typeRaw.flatMap(SessionType.init(rawValue:)) {
                        Text("\(type.emoji) \(type.label)").font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                    }
                    let weekly = weeklyPoints(rows)
                    if weekly.count > 1 {
                        Chart(weekly) { point in
                            BarMark(x: .value("w", point.weekStart, unit: .weekOfYear), y: .value("h", point.seconds / 3600))
                                .foregroundStyle(AnalyticsMetric.activity.color)
                                .cornerRadius(2)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine().foregroundStyle(AppTheme.border)
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(L("\(Int(v)) ч", "\(Int(v)) h")).font(.lora(10)).foregroundStyle(AppTheme.inkSoft)
                                    }
                                }
                            }
                        }
                        .frame(height: 120)
                        .accessibilityLabel(L("Часы по неделям", "Hours by week"))
                    }
                }
                .padding(16)
                .parchmentCard(padding: 0)

                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(title: L("Сессии", "Sessions"), value: "\(count)", route: .sessions(activity: name))
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)

                AnalyticsDisclosure(L("Настроение вокруг занятия", "Mood around the activity")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                if rows.count > 1 {
                                    Text(SessionType.label(for: row.typeRaw.flatMap(SessionType.init(rawValue:))))
                                        .font(.lora(13, weight: .medium)).foregroundStyle(AppTheme.ink)
                                }
                                Text(L(
                                    "до \(analyticsFormat(row.moodBefore.average)) → во время \(analyticsFormat(row.moodDuring.average)) → после \(analyticsFormat(row.moodAfter.average))",
                                    "before \(analyticsFormat(row.moodBefore.average)) → during \(analyticsFormat(row.moodDuring.average)) → after \(analyticsFormat(row.moodAfter.average))"
                                ))
                                .font(.lora(13)).foregroundStyle(AppTheme.ink)
                                Text(L(
                                    "энергия \(analyticsFormat(row.energy.average)) · мотивация \(analyticsFormat(row.motivation.average))",
                                    "energy \(analyticsFormat(row.energy.average)) · motivation \(analyticsFormat(row.motivation.average))"
                                ))
                                .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                if let delta = row.moodDelta {
                                    Text(L("к личному среднему \(String(format: "%+.1f", delta))", "vs personal average \(String(format: "%+.1f", delta))"))
                                        .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                }
                                AnalyticsReliabilityBadge(confidence: row.confidence, extra: L("единица: сессии", "unit: sessions"))
                            }
                        }
                    }
                }
            }
        }
    }

    private func weeklyPoints(_ rows: [AnalyticsActivityRow]) -> [AnalyticsWeekPoint] {
        var merged: [Date: AnalyticsWeekPoint] = [:]
        for row in rows {
            for point in row.weekly {
                if var existing = merged[point.weekStart] {
                    existing.seconds += point.seconds
                    existing.sessionCount += point.sessionCount
                    merged[point.weekStart] = existing
                } else {
                    merged[point.weekStart] = point
                }
            }
        }
        return merged.values.sorted { $0.weekStart < $1.weekStart }
    }
}
