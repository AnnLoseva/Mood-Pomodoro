import SwiftUI

/// Эмоции и импульсы: what was marked, on how many days, and the mood that
/// went with those days. A day with no mark is "no mark", never "no impulse".
struct EmotionsAnalyticsView: View {
    @Bindable var store: AnalyticsStore

    var body: some View {
        let snapshot = store.snapshot
        AnalyticsDetailScaffold(title: AnalyticsSection.emotions.title, store: store) {
            if snapshot.emotions.isEmpty && snapshot.impulses.isEmpty {
                AnalyticsEmptyCard(
                    title: L("Отметок нет", "No marks"),
                    message: L("Эмоции и импульсы отмечаются в сессии или в Дневнике.", "Emotions and impulses are marked in a session or the Diary.")
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(title: AnalyticsRecordKind.emotions.title, value: "\(snapshot.emotions.reduce(0) { $0 + $1.entryCount })", route: .records(.emotions))
                    Divider().overlay(AppTheme.border)
                    AnalyticsRouteRow(title: AnalyticsRecordKind.impulses.title, value: "\(snapshot.impulses.reduce(0) { $0 + $1.entryCount })", route: .records(.impulses))
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)

                if !snapshot.emotions.isEmpty {
                    AnalyticsDisclosure(L("Эмоции", "Emotions"), summary: "\(snapshot.emotions.count)", open: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(snapshot.emotions) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(Emotion(rawValue: row.raw)?.label ?? row.raw).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                        Spacer(minLength: 8)
                                        Text(L("\(row.dayCount) дн.", "\(row.dayCount) d")).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                    }
                                    Text(L("настроение \(analyticsFormat(row.mood.average)) · энергия \(analyticsFormat(row.energy.average))",
                                           "mood \(analyticsFormat(row.mood.average)) · energy \(analyticsFormat(row.energy.average))"))
                                        .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                    if let sleep = row.previousNightSleep {
                                        Text(L("сон этой ночи \(analyticsDuration(sleep))", "that night's sleep \(analyticsDuration(sleep))"))
                                            .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                                    }
                                    AnalyticsReliabilityBadge(confidence: row.mood.confidence)
                                }
                            }
                        }
                    }
                }

                if !snapshot.impulses.isEmpty {
                    AnalyticsDisclosure(L("Импульсы", "Impulses"), summary: "\(snapshot.impulses.count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(snapshot.impulses) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(ImpulseCategory(rawValue: row.categoryRaw)?.label ?? row.categoryRaw).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                        Spacer(minLength: 8)
                                        Text("\(row.entryCount)").font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                                    }
                                    Text(L("\(row.dayCount) дн. с отметками · настроение \(analyticsFormat(row.mood.average))",
                                           "\(row.dayCount) days with marks · mood \(analyticsFormat(row.mood.average))"))
                                        .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                    AnalyticsReliabilityBadge(confidence: row.mood.confidence)
                                }
                            }
                            Text(L("Отсутствие записи — это «дни без таких отметок», а не доказанное отсутствие импульса.",
                                   "A missing record is “days without those marks”, not proof there was no impulse."))
                                .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
            }
        }
    }
}
