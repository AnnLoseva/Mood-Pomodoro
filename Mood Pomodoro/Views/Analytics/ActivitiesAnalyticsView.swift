import SwiftUI
import Charts

struct ActivitiesAnalyticsView: View {
    let snapshot: AnalyticsSnapshot
    @State private var sort = Sort.duration

    private enum Sort: String, CaseIterable, Identifiable {
        case duration, sessions, mood, delta
        var id: String { rawValue }
        var title: String {
            switch self {
            case .duration: return L("Длительность", "Duration")
            case .sessions: return L("Сеансы", "Sessions")
            case .mood: return L("Настроение", "Mood")
            case .delta: return L("Изменение", "Change")
            }
        }
    }

    var body: some View {
        let rows = sorted(snapshot.activities)
        ScrollView {
            LazyVStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Sort.allCases) { item in
                            let on = sort == item
                            Button { sort = item } label: {
                                Text(item.title)
                                    .font(.lora(12, weight: on ? .semibold : .regular))
                                    .foregroundStyle(on ? AppTheme.parchmentCard : AppTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(on ? AppTheme.forest : AppTheme.chipFill))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if rows.isEmpty {
                    AnalyticsEmptyCard(
                        title: L("Нет сеансов в периоде", "No sessions in this period"),
                        message: L("Начни сессию на вкладке «Сейчас», чтобы здесь появились сравнения активностей.", "Start a session on Now so activity comparisons can appear here.")
                    )
                } else {
                    ForEach(SessionType.allCases, id: \.rawValue) { type in
                        let group = rows.filter { $0.typeRaw == type.rawValue }
                        if !group.isEmpty { section(type.label, group) }
                    }
                    let untyped = rows.filter { $0.typeRaw == nil }
                    if !untyped.isEmpty { section(SessionType.unassignedLabel, untyped) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private func sorted(_ rows: [AnalyticsActivityRow]) -> [AnalyticsActivityRow] {
        switch sort {
        case .duration: return rows.sorted { $0.totalSeconds > $1.totalSeconds }
        case .sessions: return rows.sorted { $0.sessionCount > $1.sessionCount }
        case .mood: return rows.sorted { ($0.mood.average ?? 0) > ($1.mood.average ?? 0) }
        case .delta: return rows.sorted { ($0.moodDelta ?? 0) > ($1.moodDelta ?? 0) }
        }
    }

    private func section(_ title: String, _ rows: [AnalyticsActivityRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Ldata(row.name)).font(.lora(15, weight: .medium)).foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(analyticsDuration(row.totalSeconds)).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
                    }
                    Text(
                        countLabel(row.sessionCount, ru: ("сеанс", "сеанса", "сеансов"), en: ("session", "sessions"))
                            + " · "
                            + countLabel(row.dayCount, ru: ("день", "дня", "дней"), en: ("day", "days"))
                            + L(" · средняя \(analyticsDuration(row.averageSeconds))", " · average \(analyticsDuration(row.averageSeconds))")
                    )
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
                    Text(L(
                        "до \(analyticsFormat(row.moodBefore.average)) → во время \(analyticsFormat(row.moodDuring.average)) → после \(analyticsFormat(row.moodAfter.average))",
                        "before \(analyticsFormat(row.moodBefore.average)) → during \(analyticsFormat(row.moodDuring.average)) → after \(analyticsFormat(row.moodAfter.average))"
                    ))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.ink)
                    Text(L(
                        "энергия \(analyticsFormat(row.energy.average)) · мотивация \(analyticsFormat(row.motivation.average))",
                        "energy \(analyticsFormat(row.energy.average)) · motivation \(analyticsFormat(row.motivation.average))"
                    ))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
                    if let delta = row.moodDelta {
                        Text(L("к личному среднему \(String(format: "%+.1f", delta))", "vs personal average \(String(format: "%+.1f", delta))"))
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.ink)
                    }
                    if row.weekly.count > 1 {
                        Chart(row.weekly) { point in
                            BarMark(x: .value("w", point.weekStart), y: .value("s", point.seconds / 3600))
                                .foregroundStyle(AppTheme.forest.opacity(0.7))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 36)
                        .accessibilityLabel(L("Динамика по неделям", "Weekly trend"))
                    }
                    AnalyticsReliabilityBadge(confidence: row.confidence, extra: L("единица: сеансы", "unit: sessions"))
                }
                .padding(14)
                .parchmentCard(padding: 0)
            }
        }
    }
}
