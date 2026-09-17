import SwiftUI

struct AnalyticsReliabilityBadge: View {
    let confidence: AnalyticsConfidence
    var extra: String?

    var body: some View {
        Text(extra.map { "\(confidence.shortLabel) · \($0)" } ?? confidence.shortLabel)
            .font(.lora(11))
            .foregroundStyle(AppTheme.inkSoft)
    }
}

struct AnalyticsEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }
}

struct AnalyticsStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func analyticsFormat(_ value: Double?, suffix: String = " / 5") -> String {
    guard let value else { return "—" }
    return String(format: "%.1f%@", value, suffix)
}

func analyticsDuration(_ value: TimeInterval?) -> String {
    guard let value, value > 0 else { return "—" }
    return DurationFormatting.compact(value)
}
