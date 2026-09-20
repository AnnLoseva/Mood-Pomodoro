import SwiftUI
import SwiftData

/// The Аналитика tab, reduced to what is needed to see the picture in a few
/// seconds: the period, three headline figures, one chart, and a way in to
/// everything else. All of the earlier depth is still here — one step away,
/// opened by tapping (see `AnalyticsRouteView`) — and every figure leads on
/// to the records it was computed from.
struct AnalyticsView: View {
    @Environment(AppTabs.self) private var tabs
    @Environment(\.iPadSidebarHidden) private var iPadSidebarHidden

    @State private var store = AnalyticsStore()
    @State private var path: [AnalyticsRoute] = []
    @State private var showExport = false
    @AppStorage("analytics.home.metric") private var metricRaw = AnalyticsMetric.mood.rawValue
    @AppStorage("analytics.home.compare") private var compareRaw = ""

    private var metric: AnalyticsMetric {
        AnalyticsMetric(rawValue: metricRaw) ?? .mood
    }

    private var compare: AnalyticsMetric? {
        AnalyticsMetric(rawValue: compareRaw).flatMap { $0 == metric ? nil : $0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ForestBackdrop()
                if !store.hasIngested {
                    ProgressView().tint(AppTheme.forest)
                } else if store.facts.isEmpty {
                    emptyState
                } else {
                    GeometryReader { proxy in
                        home(isWide: proxy.size.width >= 820)
                    }
                }
            }
            .hideRootNavigationBar()
            .goblinChrome()
            .background(AnalyticsDataFeeder(store: store))
            .navigationDestination(for: AnalyticsRoute.self) { route in
                AnalyticsRouteView(route: route, store: store)
            }
            .sheet(isPresented: $showExport) { ExportSheet() }
            .onAppear(perform: consumePendingRoute)
            .onChange(of: tabs.pendingAnalyticsRoute) { _, _ in consumePendingRoute() }
        }
        .environment(\.analyticsOpen, { path.append($0) })
    }

    /// A route handed over from another tab (the diary's search) opens here.
    private func consumePendingRoute() {
        guard let route = tabs.pendingAnalyticsRoute else { return }
        tabs.pendingAnalyticsRoute = nil
        path = [route]
    }

    // MARK: - Home

    private func home(isWide: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        chartCard.frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            headlineCards(vertical: true)
                            exploreCard
                        }
                        .frame(width: 320)
                    }
                } else {
                    headlineCards(vertical: false)
                    chartCard
                    exploreCard
                }
            }
            .frame(maxWidth: isWide ? 1100 : 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.leading, iPadSidebarHidden ? 56 : 16)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(L("Аналитика", "Analytics"))
                    .font(.lora(26, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                iconButton("magnifyingglass", label: L("Поиск", "Search")) { path.append(.search) }
                iconButton("square.and.arrow.up", label: L("Экспорт", "Export")) { showExport = true }
            }
            HStack(spacing: 10) {
                AnalyticsPeriodMenu(store: store)
                Text(rangeText)
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if store.isRefreshing {
                    ProgressView().controlSize(.small).tint(AppTheme.forest)
                        .accessibilityLabel(L("Обновляю аналитику", "Updating analytics"))
                }
            }
        }
        // On a card: the title must not sit straight on the forest picture.
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .parchmentCard(padding: 0)
    }

    /// "22 авг – 20 сент": the exact window, without the year when it is this one.
    private var rangeText: String {
        let interval = store.snapshot.interval
        guard interval.start > .distantPast else { return "" }
        let last = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        if Calendar.current.isDate(interval.start, inSameDayAs: last) { return DateFormatting.fullDate(last) }
        return DateFormatting.compactDate(interval.start) + " – " + DateFormatting.compactDate(last)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.forest)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Headline figures

    private struct Headline: Identifiable {
        let metric: AnalyticsMetric
        let value: String
        let unit: String?
        let caption: String
        var id: String { metric.rawValue }
    }

    private var headlines: [Headline] {
        let o = store.snapshot.overview
        let activeSeconds = o.restSeconds + o.workSeconds + o.studySeconds + o.untypedSeconds
        return [
            Headline(
                metric: .mood,
                value: o.mood.average == nil ? "—" : analyticsFormat(o.mood.average, suffix: ""),
                unit: o.mood.average == nil ? nil : "/ 5",
                caption: o.mood.average == nil
                    ? L("нет данных", "no data")
                    : L("по \(o.mood.dayCount) дн.", "over \(o.mood.dayCount) days")
            ),
            Headline(
                metric: .sleep,
                value: analyticsDuration(o.averageSleepSeconds),
                unit: nil,
                caption: o.nightCount == 0
                    ? L("нет данных", "no data")
                    : countLabel(o.nightCount, ru: ("ночь", "ночи", "ночей"), en: ("night", "nights"))
            ),
            Headline(
                metric: .activity,
                value: o.sessionCount == 0 ? "—" : analyticsDuration(activeSeconds),
                unit: nil,
                caption: o.sessionCount == 0
                    ? L("нет данных", "no data")
                    : countLabel(o.sessionCount, ru: ("сессия", "сессии", "сессий"), en: ("session", "sessions"))
            )
        ]
    }

    @ViewBuilder
    private func headlineCards(vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 10) { ForEach(headlines) { headlineCard($0) } }
        } else {
            HStack(spacing: 10) { ForEach(headlines) { headlineCard($0) } }
        }
    }

    private func headlineCard(_ item: Headline) -> some View {
        let selected = item.metric == metric
        return Button {
            metricRaw = item.metric.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: item.metric.shape.symbolName(filled: true))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.metric.color)
                    Text(item.metric.title)
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(item.value)
                        .font(.lora(20, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    if let unit = item.unit {
                        Text(unit).font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                    }
                }
                Text(item.caption)
                    .font(.lora(11))
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.parchmentCard))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? item.metric.color : AppTheme.border, lineWidth: selected ? 2 : 1.25)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.metric.title): \(item.value) \(item.unit ?? ""), \(item.caption)")
        .accessibilityHint(L("Показать на графике", "Show on the chart"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Chart

    private var chartCard: some View {
        let snapshot = store.snapshot
        let metrics = [metric] + (compare.map { [$0] } ?? [])
        let series = metrics.map { AnalyticsChartSeries.make(metric: $0, days: snapshot.days) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AnalyticsMetricMenu(title: L("Показатель", "Metric"), selection: Binding(
                    get: { metric },
                    set: { metricRaw = $0.rawValue }
                ))
                compareMenu
                Spacer(minLength: 0)
                AnalyticsInfoButton(text: infoText(for: metrics))
            }
            AnalyticsMetricChart(series: series, interval: snapshot.interval)
            AnalyticsLinkRow(title: L("Подробнее о показателе", "More about this metric")) {
                path.append(.metric(metric))
            }
        }
        .padding(16)
        .parchmentCard(padding: 0)
    }

    private var compareMenu: some View {
        Menu {
            if compare != nil {
                Button(role: .destructive) { compareRaw = "" } label: {
                    Label(L("Убрать сравнение", "Remove comparison"), systemImage: "xmark")
                }
            }
            Section(L("Сравнить с", "Compare with")) {
                ForEach((AnalyticsMetric.primary + AnalyticsMetric.secondary).filter { $0 != metric }) { other in
                    Button { compareRaw = other.rawValue } label: {
                        if other == compare { Label(other.title, systemImage: "checkmark") } else { Text(other.title) }
                    }
                }
            }
        } label: {
            if let compare {
                AnalyticsMetricPill(metric: compare, showsChevron: true)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text(L("Сравнить", "Compare")).font(.lora(14, weight: .medium))
                }
                .foregroundStyle(AppTheme.forestDeep)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .overlay(Capsule().stroke(AppTheme.border, style: StrokeStyle(lineWidth: 1.25, dash: [4, 3])))
            }
        }
        .accessibilityLabel(L("Сравнить с другим показателем", "Compare with another metric"))
    }

    private func infoText(for metrics: [AnalyticsMetric]) -> String {
        var lines = metrics.map { "\($0.title) — \($0.unitNote). \($0.methodNote)" }
        lines.append(L("Дни без записи остаются пропусками: линия не тянется через них.", "Days without a record stay gaps: no line is drawn across them."))
        if AnalyticsChartLayout.layout(for: metrics) == .stacked {
            lines.append(L("Величины в разных единицах показаны отдельными графиками на общей оси времени.", "Quantities in different units are drawn as separate charts on a shared time axis."))
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Explore

    private var exploreCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Исследовать данные", "Explore the data"))
                .font(.lora(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(AnalyticsSection.allCases) { section in
                    NavigationLink(value: AnalyticsRoute.section(section)) {
                        HStack(spacing: 8) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.forest)
                                .frame(width: 20)
                            Text(section.title)
                                .font(.lora(13, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.chipFill))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .parchmentCard(padding: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            MoodImage(mood: .neutral, size: 72)
            Text(L("Пока мало данных", "Not much data yet"))
                .font(.lora(19, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("Аналитика появится, когда появятся записи — сессии, дневник, сон или еда.", "Analytics will appear once there are records — sessions, diary, sleep or food."))
                .font(.lora(14))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
            Button(L("Экспорт", "Export")) { showExport = true }
                .buttonStyle(AnalyticsSmallButtonStyle())
        }
        .padding(28)
        .parchmentCard()
        .padding(.horizontal, 32)
    }
}

/// Watches the data and tells the analytics store when it changed. Kept in a
/// view of its own so the heavy `@Query` collections are read here only —
/// a tap, a sheet or a chart selection elsewhere on the screen re-renders the
/// screen without walking a thousand records for a change stamp.
struct AnalyticsDataFeeder: View {
    let store: AnalyticsStore

    @Query private var checkIns: [CheckIn]
    @Query private var emotions: [EmotionEntry]
    @Query private var impulses: [ImpulseEntry]
    @Query private var support: [SupportEntry]
    @Query private var cycle: [CycleEntry]
    @Query private var sessions: [FocusSession]
    @Query private var conditionEvents: [ConditionEvent]
    @Query private var foodEntries: [FoodEntry]
    @Query private var hungerEntries: [HungerEntry]
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]
    @Environment(SleepStore.self) private var sleepStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: dataStamp) { ingest() }
    }

    private var dataStamp: String {
        let last = [
            checkIns.map(\.updatedAt).max(),
            sessions.map(\.updatedAt).max(),
            foodEntries.map(\.updatedAt).max(),
            hungerEntries.map(\.updatedAt).max(),
            emotions.map(\.updatedAt).max(),
            impulses.map(\.updatedAt).max()
        ].compactMap { $0 }.max()?.timeIntervalSince1970 ?? 0
        return "\(checkIns.count)|\(sessions.count)|\(conditionEvents.count)|\(foodEntries.count)|\(hungerEntries.count)|\(emotions.count)|\(impulses.count)|\(support.count)|\(cycle.count)|\(sleepStore.sessions.count)|\(categories.count)|\(last)"
    }

    private func ingest() {
        let facts = AnalyticsFactsCapture.capture(
            checkIns: checkIns,
            sessions: sessions,
            conditionEvents: conditionEvents,
            hunger: hungerEntries,
            food: foodEntries,
            emotions: emotions,
            impulses: impulses,
            support: support,
            cycle: cycle,
            categories: categories,
            sleep: sleepStore.sessions,
            healthCycle: sleepStore.cycleMarks,
            healthMedication: sleepStore.medicationDays
        )
        store.ingest(facts)
    }
}
