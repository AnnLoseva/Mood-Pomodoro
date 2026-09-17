import SwiftUI

struct FactorsAnalyticsView: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        let grouped = Dictionary(grouping: snapshot.factors, by: \.categoryID)
        ScrollView {
            LazyVStack(spacing: 16) {
                if snapshot.factors.isEmpty && snapshot.emotions.isEmpty && snapshot.impulses.isEmpty {
                    AnalyticsEmptyCard(
                        title: L("Нет условий в периоде", "No conditions in this period"),
                        message: L("Отмечай условия, эмоции и импульсы в сессии или дневнике — тогда здесь появятся сравнения.", "Log conditions, emotions and impulses in a session or the diary and comparisons will show up here.")
                    )
                } else {
                    positiveBlock
                    negativeBlock
                    ForEach(grouped.keys.sorted { a, b in
                        (grouped[a]?.first?.categoryName ?? "") < (grouped[b]?.first?.categoryName ?? "")
                    }, id: \.self) { id in
                        if let rows = grouped[id], let first = rows.first {
                            categoryCard(first, rows)
                        }
                    }
                    if !snapshot.emotions.isEmpty { emotionsBlock }
                    if !snapshot.impulses.isEmpty { impulsesBlock }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private var positiveBlock: some View {
        let rows = snapshot.factors.filter { ($0.moodDelta ?? 0) > 0 && $0.confidence != .insufficient }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Положительные связи", "Positive links"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            if rows.isEmpty {
                Text(L("Пока нет положительных связей с достаточным числом дней.", "No positive links with enough days yet."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(rows) { row in
                    factorRow(row)
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var negativeBlock: some View {
        let rows = snapshot.factors.filter { ($0.moodDelta ?? 0) < 0 && $0.confidence != .insufficient }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Отрицательные связи", "Negative links"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            if rows.isEmpty {
                Text(L("Пока нет отрицательных связей с достаточным числом дней.", "No negative links with enough days yet."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                ForEach(rows) { row in
                    factorRow(row)
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private func categoryCard(_ first: AnalyticsFactorRow, _ rows: [AnalyticsFactorRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(first.icon) \(Ldata(first.categoryName))")
                    .font(.lora(16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                if !first.categoryEnabled {
                    Text(L("отключено, история сохранена", "disabled, history kept"))
                        .font(.lora(11))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            ForEach(rows) { row in
                NavigationLink {
                    FactorDetailView(categoryID: row.categoryID, snapshot: snapshot)
                } label: {
                    factorRow(row)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private func factorRow(_ row: AnalyticsFactorRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Ldata(row.optionName)).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                Spacer()
                Text(analyticsFormat(row.mood.average)).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
            }
            Text(L("\(row.dayCount) дн. · \(row.sessionCount) сеансов · \(row.observationCount) отметок", "\(row.dayCount) days · \(row.sessionCount) sessions · \(row.observationCount) check-ins"))
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            if let delta = row.moodDelta {
                Text(L("к личному среднему \(String(format: "%+.1f", delta))", "vs personal average \(String(format: "%+.1f", delta))"))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.ink)
            }
            if row.confidence == .insufficient {
                Text(L("Нужно ещё \(row.neededForPreliminary) дн. для предварительного сравнения", "Need \(row.neededForPreliminary) more days for a preliminary comparison"))
                    .font(.lora(11))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                AnalyticsReliabilityBadge(confidence: row.confidence)
            }
        }
    }

    private var emotionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Эмоции", "Emotions"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            ForEach(snapshot.emotions) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Emotion(rawValue: row.raw)?.label ?? row.raw)
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(analyticsFormat(row.mood.average))
                            .font(.lora(14, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    Text(L("\(row.dayCount) дн. с такой отметкой · энергия \(analyticsFormat(row.energy.average))", "\(row.dayCount) days with this mark · energy \(analyticsFormat(row.energy.average))"))
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                    if let sleep = row.previousNightSleep {
                        Text(L("сон этой ночи \(analyticsDuration(sleep))", "that night's sleep \(analyticsDuration(sleep))"))
                            .font(.lora(11))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    AnalyticsReliabilityBadge(confidence: row.mood.confidence)
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private var impulsesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Импульсивность", "Impulsivity"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("Отсутствие записи нельзя читать как доказанное отсутствие импульса — это «дни без таких отметок».", "A missing record is not proof there was no impulse — those are “days without those marks”."))
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
            ForEach(snapshot.impulses) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ImpulseCategory(rawValue: row.categoryRaw)?.label ?? row.categoryRaw)
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(row.entryCount)")
                            .font(.lora(14, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    Text(L("\(row.dayCount) дн. с отметками · настроение \(analyticsFormat(row.mood.average))", "\(row.dayCount) days with marks · mood \(analyticsFormat(row.mood.average))"))
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                    AnalyticsReliabilityBadge(confidence: row.mood.confidence)
                }
            }
        }
        .padding(18)
        .parchmentCard()
    }
}
