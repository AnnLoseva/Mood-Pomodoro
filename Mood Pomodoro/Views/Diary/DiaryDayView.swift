//
//  DiaryDayView.swift
//  Mood Pomodoro
//

import SwiftUI
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
        Chart(summary.moodPoints) { point in
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
        .chartYScale(domain: 1...5)
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
        .frame(height: 160)
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
