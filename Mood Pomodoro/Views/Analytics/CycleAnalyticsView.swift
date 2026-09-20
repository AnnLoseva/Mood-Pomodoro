import SwiftUI

/// Цикл и препараты: only what was recorded — counts of marked days and the
/// entries themselves. No phases are inferred and nothing is interpreted.
struct CycleAnalyticsView: View {
    @Bindable var store: AnalyticsStore

    var body: some View {
        let o = store.snapshot.overview
        let days = store.snapshot.days
        let cycleDays = days.filter { $0.cycleDay != nil }.count
        AnalyticsDetailScaffold(title: AnalyticsSection.cycle.title, store: store) {
            if o.periodDayCount == 0 && o.supportTakenDays == 0 && o.supportSkippedDays == 0 && cycleDays == 0 {
                AnalyticsEmptyCard(
                    title: L("Отметок нет", "No marks"),
                    message: L("Цикл и препараты отмечаются в Дневнике или подтягиваются из Apple Health.", "Cycle and medication are marked in the Diary or come from Apple Health.")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        AnalyticsStatTile(title: L("Дней менструации", "Period days"), value: "\(o.periodDayCount)")
                        AnalyticsStatTile(title: L("Принято", "Taken"), value: L("\(o.supportTakenDays) дн.", "\(o.supportTakenDays) d"))
                        AnalyticsStatTile(title: L("Не принято", "Not taken"), value: L("\(o.supportSkippedDays) дн.", "\(o.supportSkippedDays) d"))
                    }
                    Text(L("День без отметки — «не отмечено», а не «не принято» и не «без менструации».", "A day without a mark is “not recorded”, not “not taken” and not “no period”."))
                        .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .parchmentCard(padding: 0)

                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(title: AnalyticsRecordKind.cycle.title, route: .records(.cycle))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: AnalyticsRecordKind.medication.title, route: .records(.medication))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: L("Сон по фазам цикла", "Sleep by cycle phase"), route: .section(.sleep))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: L("Сравнить с настроением", "Compare with mood"), route: .section(.compare))
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)
            }
        }
    }
}
