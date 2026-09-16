//
//  DiaryDayView.swift
//  Mood Pomodoro
//

import SwiftUI
import UIKit
import Charts

/// One day, assembled from what the app recorded plus anything the user
/// added to it — including after the fact. Every manual row is tappable and
/// opens its own edit form; nothing here asks her to fill anything in.
struct DiaryDayView: View {
    let summary: DailySummary
    let isToday: Bool
    let onQuickMood: () -> Void
    let onAdd: (DiaryEntrySheet) -> Void
    let onEdit: (DiaryEditTarget) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if summary.isEmpty {
                emptyCard
            } else {
                moodCard
                if !summary.timelineEvents.isEmpty { timelineCard }
                if !summary.activities.isEmpty { studyCard }
                if !summary.conditions.isEmpty { conditionsCard }
            }
            supportCard
            cycleCard
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            MoodImage(mood: .neutral, size: 64)
            Text(isToday ? L("Сегодня пока пусто", "Nothing here yet today") : L("В этот день ничего не записано", "Nothing was recorded on this day"))
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(isToday
                 ? L("Здесь появится то, что приложение заметит за день.", "What the app notices during the day will show up here.")
                 : L("Если что-то вспомнилось — можно добавить прямо в этот день.", "If you remember something, you can add it right to this day."))
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
            if isToday {
                Button(L("Как я сейчас?", "How am I feeling?"), action: onQuickMood)
                    .buttonStyle(.goblinSecondary)
                    .padding(.top, 4)
            } else {
                Button(L("Добавить настроение", "Add mood")) { onAdd(.mood(editing: nil)) }
                    .buttonStyle(.goblinSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }

    private var moodCard: some View {
        DiaryCard(title: L("Моё состояние", "My mood")) {
            VStack(alignment: .leading, spacing: 14) {
                if let average = summary.moodStats.average {
                    HStack(alignment: .center, spacing: 14) {
                        // The same color the day has in the month calendar.
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(MoodColorScale.color(for: average))
                            .frame(width: 12, height: 46)
                        MoodAverageLabel(average: average)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(summary.moodStats.checkInCount)")
                                .font(.lora(20, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("check-in")
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                    if summary.moodStats.checkInCount < 3 {
                        DiaryNote(text: L("Отметок за день мало — это просто то, что было записано, а не картина всего дня.", "Only a few entries — this is just what was recorded, not the whole picture of the day."))
                    }
                } else {
                    DiaryNote(text: L("Настроение за этот день не отмечено.", "No mood was recorded for this day."))
                }

                if summary.moodPoints.count >= 2 {
                    dayChart
                }

                if let firstDifficult = summary.moodStats.firstDifficultMoodAt {
                    DiaryNote(text: L("Первое 🥲 / 😭 — в \(DateFormatting.time(firstDifficult)).", "First 🥲 / 😭 at \(DateFormatting.time(firstDifficult))."))
                }

                if isToday {
                    Button(L("Как я сейчас?", "How am I feeling?"), action: onQuickMood)
                        .buttonStyle(.goblinSecondary)
                } else {
                    Button(L("Добавить настроение", "Add mood")) { onAdd(.mood(editing: nil)) }
                        .buttonStyle(.goblinSecondary)
                }
            }
        }
    }

    private var dayChart: some View {
        let hasActivities = !summary.activitySpans.isEmpty
        return Chart {
            // Activities first, so the mood line is drawn over them.
            ForEach(summary.activitySpans) { span in
                ForEach(span.workIntervals, id: \.self) { interval in
                    RectangleMark(
                        xStart: .value("Начало", interval.start),
                        xEnd: .value("Конец", interval.end),
                        yStart: .value("Состояние", 1.0),
                        yEnd: .value("Состояние", 5.0)
                    )
                    .foregroundStyle(activityColor(for: span).opacity(0.22))
                }
                // Marks where it began — and keeps a few-minute session,
                // too narrow for its band to show, visible at all.
                RuleMark(
                    x: .value("Начало", span.start),
                    yStart: .value("Состояние", 1.0),
                    yEnd: .value("Состояние", 5.0)
                )
                .foregroundStyle(activityColor(for: span).opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(summary.moodPoints) { point in
                LineMark(
                    x: .value("Время", point.timestamp),
                    y: .value("Состояние", point.mood.scale)
                )
                .foregroundStyle(AppTheme.forest)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Время", point.timestamp),
                    y: .value("Состояние", point.mood.scale)
                )
                .foregroundStyle(point.origin == .manual ? AppTheme.rust : AppTheme.forestDeep)
            }
        }
        // The space above 5 holds the activity labels.
        .chartYScale(domain: 1...(hasActivities ? 6 : 5))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if hasActivities, let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    ForEach(placedActivityLabels(proxy: proxy, plot: plot)) { label in
                        HStack(spacing: Self.labelDotSpacing) {
                            Circle()
                                .fill(label.color)
                                .frame(width: Self.labelDotSize, height: Self.labelDotSize)
                            Text(label.name)
                                .font(.custom(Self.labelFontName, fixedSize: Self.labelFontSize))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(width: label.width, height: Self.labelLaneHeight, alignment: .leading)
                        .offset(x: label.x, y: plot.minY + CGFloat(label.lane) * Self.labelLaneHeight)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let raw = value.as(Int.self),
                   let mood = Mood.orderedCases.first(where: { Int($0.scale) == raw }) {
                    AxisValueLabel { Text(mood.emoji) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(AppTheme.border)
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(DateFormatting.time(date))
                            .font(.lora(10))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }
        }
        .frame(height: hasActivities ? 190 : 160)
    }

    // MARK: - Activity labels on the day chart

    private struct PlacedActivityLabel: Identifiable {
        let id: UUID
        let name: String
        let color: Color
        let x: CGFloat
        let lane: Int
        let width: CGFloat
    }

    /// Muted woodland tones that stay distinct from the forest-green mood line.
    private static let activityPalette: [Color] = [
        AppTheme.moss,
        Color(red: 0.769, green: 0.584, blue: 0.259),
        Color(red: 0.357, green: 0.463, blue: 0.541),
        Color(red: 0.522, green: 0.365, blue: 0.447),
        AppTheme.rust
    ]

    private static let labelFontName = "Lora-Medium"
    private static let labelFontSize: CGFloat = 10
    private static let labelDotSize: CGFloat = 6
    private static let labelDotSpacing: CGFloat = 3
    private static let labelLaneHeight: CGFloat = 14
    private static let labelLaneCount = 2
    private static let labelGap: CGFloat = 6
    private static let labelFont = UIFont(name: labelFontName, size: labelFontSize)
        ?? .systemFont(ofSize: labelFontSize, weight: .medium)

    /// The same activity keeps one color through the day.
    private func activityColor(for span: ActivitySpan) -> Color {
        var names: [String] = []
        for other in summary.activitySpans where !names.contains(other.activityName) {
            names.append(other.activityName)
        }
        let index = names.firstIndex(of: span.activityName) ?? 0
        return Self.activityPalette[index % Self.activityPalette.count]
    }

    /// Each label starts where its activity starts and sits in the first of
    /// two lanes above the chart with room for it. A short session is often
    /// narrower than its name, so labels may run past their band — but never
    /// over another label; one that can't fit anywhere is shifted right and
    /// truncated, or left out if there is no room at all.
    private func placedActivityLabels(proxy: ChartProxy, plot: CGRect) -> [PlacedActivityLabel] {
        var laneEnds = Array(repeating: -CGFloat.infinity, count: Self.labelLaneCount)
        return summary.activitySpans.compactMap { span in
            guard let startX = proxy.position(forX: span.start) else { return nil }
            let name = span.activityName.isEmpty ? L("Сессия", "Session") : Ldata(span.activityName)
            let textWidth = (name as NSString).size(withAttributes: [.font: Self.labelFont]).width
            let naturalWidth = ceil(textWidth) + Self.labelDotSize + Self.labelDotSpacing + 2
            let preferredX = max(plot.minX, min(plot.minX + startX, plot.maxX - naturalWidth))

            let lane: Int
            var x = preferredX
            if let free = laneEnds.firstIndex(where: { $0 + Self.labelGap <= preferredX }) {
                lane = free
            } else {
                lane = laneEnds.indices.min { laneEnds[$0] < laneEnds[$1] } ?? 0
                x = laneEnds[lane] + Self.labelGap
            }
            let width = min(naturalWidth, plot.maxX - x)
            guard width >= Self.labelDotSize + Self.labelDotSpacing + 16 else { return nil }
            laneEnds[lane] = x + width
            return PlacedActivityLabel(
                id: span.id,
                name: name,
                color: activityColor(for: span),
                x: x,
                lane: lane,
                width: width
            )
        }
    }

    private var timelineCard: some View {
        DiaryCard(title: L("День", "Day"), subtitle: L("Нажми на запись, чтобы изменить", "Tap an entry to edit it")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summary.timelineEvents) { event in
                    if let target = event.target {
                        Button {
                            onEdit(target)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                TimelineRow(event: event)
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.inkSoft)
                                    .padding(.top, 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        TimelineRow(event: event)
                    }
                }
            }
        }
    }

    private var studyCard: some View {
        DiaryCard(title: L("📚 Учёба", "📚 Study")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    stat(title: L("Активно", "Active"), value: DurationFormatting.compact(summary.totalActiveDuration))
                    if summary.totalBreakDuration > 0 {
                        stat(title: L("Перерывы", "Breaks"), value: DurationFormatting.compact(summary.totalBreakDuration))
                    }
                    stat(title: L("Сессий", "Sessions"), value: "\(summary.sessionCount)")
                }
                Divider().background(AppTheme.border)
                VStack(spacing: 12) {
                    ForEach(summary.activities) { activity in
                        ActivityStatRow(stats: activity)
                    }
                }
            }
        }
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conditionsCard: some View {
        DiaryCard(title: L("☕ Условия дня", "☕ Today's conditions")) {
            FlowLayout(spacing: 8) {
                ForEach(summary.conditions, id: \.optionID) { entry in
                    let chip = entry.asChip
                    HStack(spacing: 5) {
                        FactorIconView(icon: chip.icon, iconImageName: chip.iconImageName, size: 18)
                        Text(chip.name)
                            .font(.lora(13, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(AppTheme.parchment.opacity(0.6)))
                    .overlay(Capsule(style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                }
            }
        }
    }

    /// Tracking only — the card states the mark and offers to change it,
    /// nothing else. "Не отмечено" is shown as its own state.
    private var supportCard: some View {
        DiaryCard(title: L("💊 Ежедневная поддержка", "💊 Daily support")) {
            HStack(spacing: 10) {
                Text(supportLine)
                    .font(.lora(15, weight: summary.support == nil ? .regular : .medium))
                    .foregroundStyle(summary.support == nil ? AppTheme.inkSoft : AppTheme.ink)
                Spacer(minLength: 8)
                Button(summary.support == nil ? L("Отметить", "Mark") : L("Изменить", "Change")) { onAdd(.support) }
                    .font(.lora(13, weight: .medium))
                    .foregroundStyle(AppTheme.forest)
                    .buttonStyle(.plain)
            }
        }
    }

    private var supportLine: String {
        guard let support = summary.support else { return L("— Не отмечено", "— Not recorded") }
        let when = support.time.map(DateFormatting.time) ?? L("в течение дня", "during the day")
        return "\(support.status.glyph) \(support.status.label) · \(when)"
    }

    private var cycleCard: some View {
        DiaryCard(title: L("🌸 Цикл", "🌸 Cycle")) {
            VStack(alignment: .leading, spacing: 10) {
                if summary.isPeriodDay {
                    Text(summary.cycleDay.map { L("🌸 Менструация — день \($0)", "🌸 Period — day \($0)") } ?? L("🌸 Менструация", "🌸 Period"))
                        .font(.lora(15, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                } else if let day = summary.cycleDay {
                    HStack(spacing: 8) {
                        Text(L("День цикла", "Cycle day"))
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.inkSoft)
                        Spacer()
                        Text("\(day)")
                            .font(.lora(20, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                } else {
                    DiaryNote(text: L("Цикл не отмечен — можно вести, если хочется, и не вести, если нет.", "No cycle recorded — track it if you'd like to, skip it if not."))
                }

                ForEach(summary.cycleEvents, id: \.self) { event in
                    Text("\(event.icon) \(event.label)")
                        .font(.lora(13))
                        .foregroundStyle(AppTheme.inkSoft)
                }

                Button(summary.cycleEvents.isEmpty ? L("Отметить", "Mark") : L("Изменить отметку", "Change mark")) { onAdd(.cycle) }
                    .font(.lora(13, weight: .medium))
                    .foregroundStyle(AppTheme.forest)
                    .buttonStyle(.plain)
            }
        }
    }
}
