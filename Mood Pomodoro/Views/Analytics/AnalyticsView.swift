import SwiftUI
import SwiftData

struct AnalyticsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview, activities, conditions, food, sleep, compare
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return L("Обзор", "Overview")
            case .activities: return L("Активности", "Activities")
            case .conditions: return L("Состояния", "States")
            case .food: return L("Еда", "Food")
            case .sleep: return L("Сон", "Sleep")
            case .compare: return L("Сравнение", "Compare")
            }
        }
    }

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
    @Environment(\.iPadSidebarHidden) private var iPadSidebarHidden

    @State private var store = AnalyticsStore()
    @State private var section: Section = .overview
    @State private var showExport = false
    @State private var showCustomDates = false

    private var hasAnyData: Bool {
        !checkIns.isEmpty || !sessions.isEmpty || !emotions.isEmpty || !impulses.isEmpty
            || !support.isEmpty || !cycle.isEmpty || !foodEntries.isEmpty || !hungerEntries.isEmpty
            || !sleepStore.sessions.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()
                if !hasAnyData {
                    emptyState
                        .overlay(alignment: .topTrailing) {
                            Button { showExport = true } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(AppTheme.forest)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Экспорт", "Export"))
                            .padding(.trailing, 8)
                        }
                } else {
                    VStack(spacing: 0) {
                        periodBar
                        sectionPicker
                        if store.isRefreshing {
                            ProgressView()
                                .tint(AppTheme.forest)
                                .padding(.bottom, 6)
                                .accessibilityLabel(L("Обновляю аналитику", "Updating analytics"))
                        }
                        Group {
                            switch section {
                            case .overview: OverviewAnalyticsView(snapshot: store.snapshot)
                            case .activities: ActivitiesAnalyticsView(snapshot: store.snapshot)
                            case .conditions: FactorsAnalyticsView(snapshot: store.snapshot)
                            case .food: FoodAnalyticsView(snapshot: store.snapshot)
                            case .sleep: SleepAnalyticsView(snapshot: store.snapshot)
                            case .compare: CompareAnalyticsView(snapshot: store.snapshot)
                            }
                        }
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .hideRootNavigationBar()
            .goblinChrome()
            .sheet(isPresented: $showExport) { ExportSheet() }
            .sheet(isPresented: $showCustomDates) { customDatesSheet }
            .task(id: dataStamp) { ingest() }
        }
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

    private var periodBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AnalyticsPeriodKind.allCases) { kind in
                            let selected = store.period.kind == kind
                            Button {
                                if kind == .custom {
                                    showCustomDates = true
                                } else {
                                    store.period.kind = kind
                                }
                            } label: {
                                Text(kind.title)
                                    .font(.lora(12, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? AppTheme.parchmentCard : AppTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(selected ? AppTheme.forest : AppTheme.chipFill))
                                    .overlay(Capsule().stroke(AppTheme.border, lineWidth: selected ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, iPadSidebarHidden ? 56 : 20)
                }
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppTheme.forest)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Экспорт", "Export"))
                .padding(.trailing, 12)
            }
        }
        .padding(.top, 4)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Section.allCases) { item in
                    let selected = item == section
                    Button { section = item } label: {
                        Text(item.title)
                            .font(.lora(12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AppTheme.parchmentCard : AppTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selected ? AppTheme.forest : AppTheme.chipFill))
                            .overlay(Capsule().stroke(AppTheme.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, iPadSidebarHidden ? 56 : 20)
            .padding(.trailing, 20)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private var customDatesSheet: some View {
        NavigationStack {
            Form {
                DatePicker(L("С", "From"), selection: Binding(
                    get: { store.period.customStart ?? Date.now },
                    set: { store.period.customStart = $0; store.period.kind = .custom }
                ), displayedComponents: .date)
                DatePicker(L("По", "To"), selection: Binding(
                    get: { store.period.customEnd ?? Date.now },
                    set: { store.period.customEnd = $0; store.period.kind = .custom }
                ), displayedComponents: .date)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.parchmentCard)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово", "Done")) { showCustomDates = false }
                        .foregroundStyle(AppTheme.forest)
                }
            }
        }
        .goblinChrome()
        .presentationDetents([.medium])
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
        }
        .padding(28)
        .parchmentCard()
        .padding(.horizontal, 32)
    }
}
