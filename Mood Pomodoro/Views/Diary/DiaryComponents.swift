//
//  DiaryComponents.swift
//  Mood Pomodoro
//

import SwiftUI

/// Small building blocks shared by the day and month screens. Presentation
/// only — every number they show is already computed by `AnalyticsService`.

/// A titled parchment card, the diary's one repeating container.
struct DiaryCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.lora(16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .parchmentCard(padding: 0)
    }
}

/// The mushroom for an averaged mood plus its "3.4 / 5" figure. The number is
/// a summary of what was recorded, never a score the user is graded on.
struct MoodAverageLabel: View {
    let average: Double?
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            if let average {
                MoodImage(mood: .nearest(to: average), size: size)
                Text(String(format: "%.1f / 5", average))
                    .font(.lora(20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            } else {
                Text("—")
                    .font(.lora(20, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }
}

/// One "💻 Программирование · 1ч 45м · 😄 4.2" line.
struct ActivityStatRow: View {
    let stats: ActivityDurationStatistics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Ldata(stats.activityName))
                    .font(.lora(15, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                Text(detailLine)
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            Spacer(minLength: 8)
            if let average = stats.averageMood, stats.hasEnoughData {
                HStack(spacing: 6) {
                    MoodImage(mood: .nearest(to: average), size: 22)
                    Text(String(format: "%.1f", average))
                        .font(.lora(15, weight: .semibold))
                        .foregroundStyle(AppTheme.forest)
                }
            } else if stats.checkInCount > 0 {
                // Below the sample threshold we show the count instead of an
                // average, rather than implying precision that isn't there.
                Text("\(stats.checkInCount) check-in")
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private var detailLine: String {
        var parts = [DurationFormatting.compact(stats.activeDuration)]
        if stats.breakDuration > 0 {
            parts.append(L("\(DurationFormatting.compact(stats.breakDuration)) перерыв", "\(DurationFormatting.compact(stats.breakDuration)) break"))
        }
        parts.append(countLabel(stats.sessionCount, ru: ("сессия", "сессии", "сессий"), en: ("session", "sessions")))
        if stats.checkInCount > 0, stats.hasEnoughData {
            parts.append("\(stats.checkInCount) check-in")
        }
        return parts.joined(separator: " · ")
    }
}

/// Mood share per level — "😄 Хорошо — 31%".
struct MoodDistributionRows: View {
    let distribution: MoodDistribution

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Mood.orderedCases) { mood in
                let share = distribution.percentage(for: mood) ?? 0
                // Label row and bar are stacked rather than side by side: in a
                // narrow column (the iPad's two-up month layout) a bar
                // competing for the same line squeezes the label to one
                // character per line.
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        MoodImage(mood: mood, size: 22)
                        Text(mood.label)
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.lora(14, weight: .medium).monospacedDigit())
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppTheme.border.opacity(0.35))
                            Capsule()
                                .fill(AppTheme.forest.opacity(0.5))
                                .frame(width: max(0, proxy.size.width * share))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}

/// The diary's one way of saying "there isn't enough here yet" — never a
/// nudge, a streak warning, or a reminder to fill anything in.
struct DiaryNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.lora(13))
            .foregroundStyle(AppTheme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ‹ title › stepper used for both the day and the month.
struct DiaryPeriodStepper: View {
    let title: String
    var subtitle: String?
    let onPrevious: () -> Void
    let onNext: () -> Void
    var onTapTitle: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            stepButton(systemImage: "chevron.left", action: onPrevious)
            Button {
                onTapTitle?()
            } label: {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.lora(18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(onTapTitle == nil)
            stepButton(systemImage: "chevron.right", action: onNext)
        }
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.forest)
                .frame(width: 38, height: 38)
                .background(Circle().fill(AppTheme.parchmentCard))
                .overlay(Circle().stroke(AppTheme.border, lineWidth: 1.25))
        }
        .buttonStyle(.plain)
    }
}
