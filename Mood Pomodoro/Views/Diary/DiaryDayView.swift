//
//  DiaryDayView.swift
//  Mood Pomodoro
//

import SwiftUI

/// One day, assembled from what the app recorded plus anything the user
/// added to it — including after the fact. Every manual row is tappable and
/// opens its own edit form; nothing here asks her to fill anything in.
struct DiaryDayView: View {
    @Environment(SleepStore.self) private var sleepStore

    let summary: DailySummary
    /// Sleep is passed in rather than queried: it lives in the local-only
    /// health store, outside the CloudKit container the rest of the diary
    /// reads through `@Query`.
    let sleep: SleepDaySummary
    let isToday: Bool
    let onQuickMood: () -> Void
    let onAdd: (DiaryEntrySheet) -> Void
    let onEdit: (DiaryEditTarget) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // A night with no check-ins is still a day with something in it.
            if summary.isEmpty && sleep.isEmpty {
                emptyCard
            } else {
                DayMarkersRow(summary: summary, sleep: sleep)
                if !summary.isEmpty {
                    moodCard
                    if !summary.timelineEvents.isEmpty { timelineCard }
                    if !summary.food.isEmpty { foodCard }
                    if !summary.activities.isEmpty { studyCard }
                    if !summary.conditions.isEmpty { conditionsCard }
                }
            }
            if summary.food.isEmpty { addFoodCard }
            sleepCard
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

                if hasChartableDay {
                    DayMetricsChart(summary: summary)
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

    /// Two points on any one series is the least that makes a line worth
    /// drawing; a single check-in is already in the timeline below.
    private var hasChartableDay: Bool {
        DayMetric.allCases.contains { summary.points(for: $0).count >= 2 }
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

    /// The day's food, as it was recorded — counts and times, nothing else.
    /// No score, no "хорошо/плохо поела", no calories: the question this
    /// answers is "как я ела", not "правильно ли я ела".
    private var foodCard: some View {
        DiaryCard(title: L("🍽 Еда", "🍽 Food")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    stat(title: L("Приёмов еды", "Meals"), value: "\(summary.food.mealCount)")
                    if let hunger = summary.food.averageHungerBeforeMeals {
                        stat(
                            title: L("Голод перед едой", "Hunger before meals"),
                            value: String(format: "%.1f / 5", hunger)
                        )
                    }
                    if let appetite = summary.food.averageAppetite {
                        stat(title: L("Аппетит", "Appetite"), value: String(format: "%.1f / 5", appetite))
                    }
                }

                if !summary.food.categoryCounts.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(summary.food.categoryCounts) { item in
                            HStack(spacing: 5) {
                                Image(item.category.imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                                Text("\(item.category.label) — \(item.count)")
                                    .font(.lora(13))
                                    .foregroundStyle(AppTheme.ink)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule(style: .continuous).fill(AppTheme.chipFill))
                            .overlay(Capsule(style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                        }
                    }
                }

                if !foodRows.isEmpty {
                    Divider().background(AppTheme.border)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(foodRows) { event in
                            Button {
                                if let target = event.target { onEdit(target) }
                            } label: {
                                TimelineRow(event: event).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if summary.food.averageHunger != nil || summary.food.averageAppetite != nil {
                    DiaryNote(text: hungerAppetiteLine)
                }
                addFoodButtons
            }
        }
    }

    /// Food and hunger/appetite on one clock, oldest first — the same rows
    /// the day timeline shows, gathered where the food block can be read on
    /// its own.
    private var foodRows: [TimelineEvent] {
        summary.timelineEvents.filter { $0.kind == .food || $0.kind == .hunger }
    }

    private var hungerAppetiteLine: String {
        var parts: [String] = []
        if let hunger = summary.food.averageHunger {
            parts.append(L("средний голод \(String(format: "%.1f", hunger))", "average hunger \(String(format: "%.1f", hunger))"))
        }
        if let appetite = summary.food.averageAppetite {
            parts.append(L("средний аппетит \(String(format: "%.1f", appetite))", "average appetite \(String(format: "%.1f", appetite))"))
        }
        let figures = parts.joined(separator: ", ")
        return L("За день: \(figures). Голод и аппетит считаются отдельно — это разные вещи.", "Today: \(figures). Hunger and appetite are counted separately — they're different things.")
    }

    /// Shown on its own when nothing was eaten *that was written down* —
    /// phrased as an offer, never as a missing entry to fill in.
    private var addFoodCard: some View {
        DiaryCard(title: L("🍽 Еда", "🍽 Food")) {
            VStack(alignment: .leading, spacing: 10) {
                DiaryNote(text: L("Еда за этот день не отмечена.", "No food recorded for this day."))
                addFoodButtons
            }
        }
    }

    private var addFoodButtons: some View {
        HStack(spacing: 14) {
            Button(L("Добавить еду", "Add food")) { onAdd(.food(editing: nil)) }
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .buttonStyle(.plain)
            Button(L("Голод / аппетит", "Hunger / appetite")) { onAdd(.hunger(editing: nil)) }
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private var studyCard: some View {
        DiaryCard(title: L("🌿 Занятия", "🌿 Activities")) {
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
                    ForEach(summary.sessionTypes) { item in
                        Text("\(SessionType.label(for: item.type)) · \(item.sessionCount) · \(DurationFormatting.compact(item.activeDuration))")
                            .font(.lora(13)).foregroundStyle(AppTheme.ink)
                    }
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
                    .background(Capsule(style: .continuous).fill(AppTheme.chipFill))
                    .overlay(Capsule(style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                }
            }
        }
    }

    private var sleepCard: some View {
        SleepCard(
            summary: sleep,
            isConnected: sleepStore.isHealthKitEnabled,
            isAvailable: sleepStore.isHealthKitAvailable,
            isImporting: sleepStore.isImporting,
            needsAdditionalPermission: sleepStore.needsAdditionalPermission,
            onConnect: { Task { await sleepStore.connectHealthKit() } },
            onRefresh: { Task { await sleepStore.refreshRequestingAccessIfNeeded() } },
            onAddManual: { onAdd(.sleep(editing: nil)) },
            onEdit: { onEdit(.sleep($0)) }
        )
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
            healthSupportActions
        }
    }

    /// Pills logged in the Health app are read on launch and whenever the
    /// app comes to the front; this is the same read on demand, so nothing
    /// has to be typed in twice.
    @ViewBuilder
    private var healthSupportActions: some View {
        if sleepStore.isHealthKitAvailable {
            if !sleepStore.isHealthKitEnabled {
                Button(L("Подключить Apple Health", "Connect Apple Health")) {
                    Task { await sleepStore.connectHealthKit() }
                }
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .buttonStyle(.plain)
            } else if sleepStore.isMedicationAvailable {
                Button(sleepStore.isImporting ? L("Обновляю…", "Refreshing…") : L("Обновить из Здоровья", "Refresh from Health")) {
                    Task { await sleepStore.refreshRequestingAccessIfNeeded() }
                }
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .buttonStyle(.plain)
                .disabled(sleepStore.isImporting)
                if sleepStore.needsMedicationPermission {
                    DiaryNote(text: L("Нажми «Обновить» — Health спросит, какие лекарства показывать здесь. Дальше приём будет подтягиваться сам при входе в приложение.", "Tap “Refresh” — Health will ask which medications to show here. After that, doses are read on their own when you open the app."))
                }
            } else {
                DiaryNote(text: L("Приём таблеток читается из Health только на iOS 26 и новее.", "Medication is read from Health only on iOS 26 and later."))
            }
        }
    }

    /// Names the source when the mark came from Apple Health, so a day the
    /// user didn't mark herself never looks like one she did.
    private var supportLine: String {
        guard let support = summary.support else { return L("— Не отмечено", "— Not recorded") }
        var parts = ["\(support.status.glyph) \(support.status.label)"]
        if support.source == .healthKit {
            parts.append(L("из Apple Health", "from Apple Health"))
            if let detail = support.note { parts.append(detail) }
        } else {
            parts.append(support.time.map(DateFormatting.time) ?? L("в течение дня", "during the day"))
        }
        return parts.joined(separator: " · ")
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

                if sleepStore.isHealthKitEnabled, !sleepStore.cycleMarks.isEmpty {
                    DiaryNote(text: L("Дни менструации подтягиваются и из Apple Health — там, где ты не отметила их сама.", "Period days are also read from Apple Health — for the days you didn't mark yourself."))
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
