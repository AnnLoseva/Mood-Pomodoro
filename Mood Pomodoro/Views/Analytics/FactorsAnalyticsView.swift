import SwiftUI

/// Факторы: the conditions that were recorded, by category. A category opens
/// its options with their counts and the mood that went with them.
struct FactorsAnalyticsView: View {
    @Bindable var store: AnalyticsStore

    var body: some View {
        let snapshot = store.snapshot
        let grouped = Dictionary(grouping: snapshot.factors, by: \.categoryID)
        let ids = grouped.keys.sorted { (grouped[$0]?.first?.categoryName ?? "") < (grouped[$1]?.first?.categoryName ?? "") }
        AnalyticsDetailScaffold(title: AnalyticsSection.factors.title, store: store) {
            if ids.isEmpty {
                AnalyticsEmptyCard(
                    title: L("Нет условий в периоде", "No conditions in this period"),
                    message: L("Отмечай условия в сессии или Дневнике — тогда здесь появятся сравнения.", "Log conditions in a session or the Diary and comparisons will show up here.")
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        if let rows = grouped[id], let first = rows.first {
                            if index > 0 { Divider().overlay(AppTheme.border) }
                            AnalyticsRouteRow(
                                title: "\(first.icon) \(Ldata(first.categoryName))",
                                subtitle: first.categoryEnabled
                                    ? L("\(rows.count) вариантов", "\(rows.count) options")
                                    : L("отключено, история сохранена", "disabled, history kept"),
                                value: "\(rows.reduce(0) { $0 + $1.dayCount }) " + L("дн.", "d"),
                                route: .factorCategory(id)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)
            }
        }
    }
}
