import SwiftUI
import SwiftData

/// Comparisons inside the existing Analytics / Compare screen.
struct DayContextComparison: View {
    @Query private var checkIns: [CheckIn]
    @Query private var sessions: [FocusSession]
    @Query private var food: [FoodEntry]
    @Query private var hunger: [HungerEntry]
    @Query private var emotions: [EmotionEntry]
    @Query private var impulses: [ImpulseEntry]
    @Query private var support: [SupportEntry]
    @Query private var cycle: [CycleEntry]
    @Environment(SleepStore.self) private var sleep
    @State private var grouping = 0
    @State private var period = 30
    @State private var impulseCategory: ImpulseCategory?
    private var days: [DayAggregate] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        let start = Calendar.current.date(byAdding: .day, value: -period, to: end)!
        return AnalyticsService.dayAggregates(in: DateInterval(start: start, end: end), checkIns: checkIns, sessions: sessions,
            hungerEntries: hunger, foodEntries: food, emotionEntries: emotions, impulseEntries: impulses,
            supportEntries: support, cycleMarks: cycle.map(\.mark) + sleep.cycleMarks,
            healthMedication: sleep.medicationDays, sleepSessions: sleep.sessions)
    }
    private var groups: [DayContextGroup] {
        switch grouping {
        case 0: return AnalyticsService.daysBySleepDuration(days)
        case 1: return AnalyticsService.daysBySleepQuality(days)
        case 2: return AnalyticsService.daysBySupport(days)
        case 3: return AnalyticsService.daysByPeriod(days)
        case 4: return AnalyticsService.daysByCycleStretch(days)
        case 5: return AnalyticsService.daysBySessionType(days)
        default: return AnalyticsService.daysByImpulse(days, category: impulseCategory)
        }
    }
    var body: some View {
        DiaryCard(title: L("Состояние дня", "Day context")) {
            Picker(L("Период", "Period"), selection: $period) {
                Text(L("Неделя", "Week")).tag(7)
                Text(L("Месяц", "Month")).tag(30)
                Text(L("Год", "Year")).tag(365)
            }.pickerStyle(.segmented)
            Picker(L("Сравнить по", "Compare by"), selection: $grouping) {
                Text(L("Длительности сна", "Sleep duration")).tag(0)
                Text(L("Качеству сна", "Sleep quality")).tag(1)
                Text(L("Таблеткам", "Medication")).tag(2)
                Text(L("Менструации", "Period")).tag(3)
                Text(L("Дням цикла", "Cycle days")).tag(4)
                Text(L("Типам занятий", "Session types")).tag(5)
                Text(L("Импульсам", "Impulses")).tag(6)
            }.tint(AppTheme.forest)
            if grouping == 6 {
                Picker(L("Категория", "Category"), selection: $impulseCategory) {
                    Text(L("Все", "All")).tag(ImpulseCategory?.none)
                    ForEach(ImpulseCategory.allCases) { Text($0.label).tag(Optional($0)) }
                }
            }
            DiaryNote(text: L("Средние по дням: каждый день имеет одинаковый вес. Время и события суммируются. Совпадение не означает причину.", "Daily averages: each day has equal weight. Time and events are summed. Co-occurrence is not causation."))
            if grouping == 6 {
                ForEach(ImpulseCategory.allCases) { category in
                    let count = days.reduce(0) { $0 + ($1.impulsesByCategory[category] ?? 0) }
                    Text("\(category.emoji) \(category.label): \(count) " + L("отметок импульса", "impulse records")).font(.lora(12))
                }
            }
            if groups.isEmpty { DiaryNote(text: L("Нет записей за этот период", "No records in this period")) }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(group.label) · \(group.dayCount) " + L("дн.", "days")).font(.lora(15, weight: .semibold))
                    ForEach(group.scales) { figure in
                        if figure.observationCount > 0 {
                            Text(figure.metric.label + ": " + (figure.hasEnoughData ? figure.average.map { String(format: "%.1f / 5", $0) } ?? "—" : L("мало данных", "limited data")) + L(" · \(figure.dayCount) дн., \(figure.observationCount) отметок", " · \(figure.dayCount) days, \(figure.observationCount) entries"))
                                .font(.lora(12))
                        }
                    }
                    ForEach(SessionType.allCases) { type in
                        if let duration = group.durationByType[type], duration > 0 {
                            Text(type.label + ": " + DurationFormatting.compact(duration) + L(" · \(group.sessionCountsByType[type] ?? 0) сессий", " · \(group.sessionCountsByType[type] ?? 0) sessions")).font(.lora(12))

                        }
                    }
                    if let unassigned = group.durationByType[nil], unassigned > 0 {
                        Text(SessionType.unassignedLabel + ": " + DurationFormatting.compact(unassigned)).font(.lora(12))
                    }
                    Text(L("Еда: \(group.mealCount) · Записанные импульсы: \(group.impulseCount)", "Meals: \(group.mealCount) · Recorded impulses: \(group.impulseCount)")).font(.lora(12))
                    ForEach(group.emotions) { item in
                        Text("\(item.emotion.emoji) \(item.emotion.label) · \(item.dayCount) " + L("дн.", "days")).font(.lora(12))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
        }
    }
}
