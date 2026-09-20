import SwiftUI

/// Resolves an `AnalyticsRoute` to its screen. Every screen shares the one
/// `AnalyticsStore`, so the period picked on the main screen is the period
/// everywhere below it.
struct AnalyticsRouteView: View {
    let route: AnalyticsRoute
    @Bindable var store: AnalyticsStore

    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        switch route {
        case .section(let section):
            switch section {
            case .state: StateAnalyticsView(store: store)
            case .sleep: SleepAnalyticsView(store: store)
            case .activities: ActivitiesAnalyticsView(store: store)
            case .food: FoodAnalyticsView(store: store)
            case .emotions: EmotionsAnalyticsView(store: store)
            case .factors: FactorsAnalyticsView(store: store)
            case .cycle: CycleAnalyticsView(store: store)
            case .compare: CompareAnalyticsView(store: store)
            }
        case .metric(let metric):
            MetricDetailView(metric: metric, store: store)
        case .activity(let name):
            ActivityDetailView(name: name, store: store)
        case .factorCategory(let id):
            FactorDetailView(categoryID: id, store: store)
        case .day(let day):
            DayRecordsView(day: day, store: store)
        case .session(let id):
            if let session = sessionManager.session(withID: id) {
                SessionDetailView(session: session)
            } else {
                ZStack {
                    ForestBackdrop()
                    Text(L("Эта сессия уже удалена.", "This session has been deleted."))
                        .font(.lora(15))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
        case .sessions(let activity):
            SessionsListView(activity: activity, store: store)
        case .nights:
            SleepNightsView(store: store)
        case .records(let kind):
            RecordsListView(kind: kind, store: store)
        case .search:
            AnalyticsSearchView(store: store)
        }
    }
}
