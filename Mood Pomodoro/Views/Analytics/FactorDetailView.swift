import SwiftUI

struct FactorDetailView: View {
    let categoryID: UUID
    let snapshot: AnalyticsSnapshot
    @State private var leftID: String?
    @State private var rightID: String?

    private var rows: [AnalyticsFactorRow] {
        snapshot.factors.filter { $0.categoryID == categoryID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    optionBlock(row)
                }
                if rows.count >= 2 {
                    comparison
                }
                Text(L("Показывает связь, не причину: среднее состояние в твоих наблюдениях, а не вывод о том, что помогает.", "Shows an association, not a cause: average mood in your observations, not a conclusion about what helps."))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(Ldata(rows.first?.categoryName ?? ""))
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .goblinChrome()
    }

    private func optionBlock(_ row: AnalyticsFactorRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Ldata(row.optionName))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("\(row.dayCount) дн. · \(row.sessionCount) сеансов · \(row.observationCount) отметок", "\(row.dayCount) days · \(row.sessionCount) sessions · \(row.observationCount) check-ins"))
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(L("настроение \(analyticsFormat(row.mood.average)) · энергия \(analyticsFormat(row.energy.average)) · мотивация \(analyticsFormat(row.motivation.average))", "mood \(analyticsFormat(row.mood.average)) · energy \(analyticsFormat(row.energy.average)) · motivation \(analyticsFormat(row.motivation.average))"))
                .font(.lora(13))
                .foregroundStyle(AppTheme.ink)
            if let minutes = row.minutesToDifficult {
                Text(L("до сложного состояния от начала фактора: \(Int(minutes.rounded())) мин.", "to a difficult state from when the factor started: \(Int(minutes.rounded())) min."))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            AnalyticsReliabilityBadge(confidence: row.confidence)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .parchmentCard()
    }

    private var comparison: some View {
        let left = rows.first { $0.id == leftID }
        let right = rows.first { $0.id == rightID }
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("Сравнить два варианта", "Compare two options"))
                .font(.lora(16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            picker(L("Первый", "First"), selection: $leftID, excluding: rightID)
            picker(L("Второй", "Second"), selection: $rightID, excluding: leftID)
            if let left, let right, left.id != right.id {
                let delta = (left.mood.average ?? 0) - (right.mood.average ?? 0)
                Text(L(
                    "В дни с «\(Ldata(left.optionName))» среднее настроение было \(String(format: "%+.1f", delta)) относительно «\(Ldata(right.optionName))». Связь может зависеть от других факторов.",
                    "On days with “\(Ldata(left.optionName))” average mood was \(String(format: "%+.1f", delta)) versus “\(Ldata(right.optionName))”. The link may depend on other factors."
                ))
                .font(.lora(13))
                .foregroundStyle(AppTheme.ink)
                AnalyticsReliabilityBadge(confidence: AnalyticsConfidence(independentCount: min(left.dayCount, right.dayCount)))
            }
        }
        .padding(16)
        .parchmentCard()
    }

    private func picker(_ title: String, selection: Binding<String?>, excluding: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(rows.filter { $0.id != excluding }) { row in
                        let on = selection.wrappedValue == row.id
                        Button { selection.wrappedValue = row.id } label: {
                            Text(Ldata(row.optionName))
                                .font(.lora(12, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? AppTheme.parchmentCard : AppTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(on ? AppTheme.forest : AppTheme.chipFill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
