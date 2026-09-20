import SwiftUI

/// One factor category: each option with its days, sessions and the mood
/// that went with it, and a comparison of any two options.
struct FactorDetailView: View {
    let categoryID: UUID
    @Bindable var store: AnalyticsStore
    @State private var leftID: String?
    @State private var rightID: String?

    private var rows: [AnalyticsFactorRow] {
        store.snapshot.factors.filter { $0.categoryID == categoryID }
    }

    var body: some View {
        AnalyticsDetailScaffold(title: Ldata(rows.first?.categoryName ?? ""), store: store) {
            ForEach(rows) { optionBlock($0) }
            if rows.count >= 2 { comparison }
            AnalyticsQuietNote(text: L("Связь, не причина: среднее состояние в твоих наблюдениях.", "An association, not a cause: average mood in your observations."))
        }
    }

    private func optionBlock(_ row: AnalyticsFactorRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Ldata(row.optionName)).font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                Spacer(minLength: 8)
                Text(analyticsFormat(row.mood.average)).font(.lora(16, weight: .semibold)).foregroundStyle(AnalyticsMetric.mood.textColor)
            }
            Text(L("\(row.dayCount) дн. · \(row.sessionCount) сессий · \(row.observationCount) отметок", "\(row.dayCount) days · \(row.sessionCount) sessions · \(row.observationCount) check-ins"))
                .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            Text(L("энергия \(analyticsFormat(row.energy.average)) · мотивация \(analyticsFormat(row.motivation.average))", "energy \(analyticsFormat(row.energy.average)) · motivation \(analyticsFormat(row.motivation.average))"))
                .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            if let delta = row.moodDelta {
                Text(L("к личному среднему \(String(format: "%+.1f", delta))", "vs personal average \(String(format: "%+.1f", delta))"))
                    .font(.lora(12)).foregroundStyle(AppTheme.ink)
            }
            if let minutes = row.minutesToDifficult {
                Text(L("до сложного состояния от начала: \(Int(minutes.rounded())) мин.", "to a difficult state from the start: \(Int(minutes.rounded())) min."))
                    .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            }
            if row.confidence == .insufficient {
                Text(L("Нужно ещё \(row.neededForPreliminary) дн. для предварительного сравнения", "Need \(row.neededForPreliminary) more days for a preliminary comparison"))
                    .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
            } else {
                AnalyticsReliabilityBadge(confidence: row.confidence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .parchmentCard(padding: 0)
    }

    private var comparison: some View {
        let left = rows.first { $0.id == leftID }
        let right = rows.first { $0.id == rightID }
        return AnalyticsDisclosure(L("Сравнить два варианта", "Compare two options")) {
            VStack(alignment: .leading, spacing: 10) {
                optionMenu(L("Первый", "First"), selection: $leftID, excluding: rightID)
                optionMenu(L("Второй", "Second"), selection: $rightID, excluding: leftID)
                if let left, let right, left.id != right.id {
                    let delta = (left.mood.average ?? 0) - (right.mood.average ?? 0)
                    Text(L("В дни с «\(Ldata(left.optionName))» среднее настроение было \(String(format: "%+.1f", delta)) относительно «\(Ldata(right.optionName))».",
                           "On days with “\(Ldata(left.optionName))” average mood was \(String(format: "%+.1f", delta)) versus “\(Ldata(right.optionName))”."))
                        .font(.lora(13)).foregroundStyle(AppTheme.ink)
                    AnalyticsReliabilityBadge(confidence: AnalyticsConfidence(independentCount: min(left.dayCount, right.dayCount)))
                }
            }
        }
    }

    private func optionMenu(_ title: String, selection: Binding<String?>, excluding: String?) -> some View {
        Menu {
            ForEach(rows.filter { $0.id != excluding }) { row in
                Button(Ldata(row.optionName)) { selection.wrappedValue = row.id }
            }
        } label: {
            HStack {
                Text(title).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                Text(rows.first { $0.id == selection.wrappedValue }.map { Ldata($0.optionName) } ?? L("выбрать", "choose"))
                    .font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Capsule().fill(AppTheme.chipFill))
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }
    }
}
