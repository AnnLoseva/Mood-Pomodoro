//
//  DiaryExporter.swift
//  Mood Pomodoro
//

import Foundation

/// Turns the diary into something to paste into an AI chat or hand to a
/// therapist: readable Markdown (with a short legend and an optional
/// prompt) or structured JSON. Pure — plain arrays in, a `String` out — and
/// built on the same `AnalyticsService` day summaries the Дневник screens
/// use, so the export never says something the app itself doesn't.
///
/// The export's language is chosen separately from the UI's (an English
/// file from a Russian-language app), via `AppLanguage.override`.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json

    var id: String { rawValue }
    var fileExtension: String { self == .markdown ? "md" : "json" }
}

struct ExportOptions: Equatable {
    var start: Date
    var end: Date
    var language: AppLanguage
    var format: ExportFormat = .markdown
    var includeAIPrompt = true
    var includeNotes = true
    var includeCycle = true
    var includeSupport = true
    var includeFood = true
}

struct ExportInput {
    var sessions: [FocusSession] = []
    var checkIns: [CheckIn] = []
    var cycleEntries: [CycleEntry] = []
    var supportEntries: [SupportEntry] = []
    var notes: [JournalNote] = []
    var conditionEvents: [ConditionEvent] = []
    var foodEntries: [FoodEntry] = []
    var hungerEntries: [HungerEntry] = []
    var emotionEntries: [EmotionEntry] = []
    var impulseEntries: [ImpulseEntry] = []
    var manualSleep: [SleepSessionSummary] = []

    /// When anything was first recorded — where "all time" starts.
    var earliestDate: Date? {
        let dates = sessions.map(\.startDate) + checkIns.map(\.timestamp) + cycleEntries.map(\.date)
            + supportEntries.map(\.day) + notes.map(\.timestamp) + conditionEvents.map(\.timestamp)
            + foodEntries.map(\.eventDate) + hungerEntries.map(\.eventDate)
        return (dates + emotionEntries.map(\.eventDate) + impulseEntries.map(\.eventDate) + manualSleep.filter { $0.source == .manual }.map(\.day)).min()
    }
}

enum DiaryExporter {
    static func export(
        _ input: ExportInput,
        options: ExportOptions,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        AppLanguage.$override.withValue(options.language) {
            let builder = ExportBuilder(input: input, options: options, calendar: calendar, now: now)
            switch options.format {
            case .markdown: return builder.markdown()
            case .json: return builder.json()
            }
        }
    }

    static func fileName(for options: ExportOptions, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: min(options.start, options.end))
        let end = formatter.string(from: max(options.start, options.end))
        return "mood-diary_\(start)_\(end).\(options.format.fileExtension)"
    }
}

private struct ExportBuilder {
    let input: ExportInput
    let options: ExportOptions
    let calendar: Calendar
    let now: Date

    /// Whole days, first through last inclusive.
    var interval: DateInterval {
        let start = calendar.startOfDay(for: min(options.start, options.end))
        let lastDay = calendar.startOfDay(for: max(options.start, options.end))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return DateInterval(start: start, end: end)
    }

    var days: [Date] {
        var result: [Date] = []
        var day = interval.start
        while day < interval.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    var lastDay: Date { days.last ?? interval.start }

    func inRange(_ date: Date) -> Bool { interval.contains(date) }

    func summary(for day: Date) -> DailySummary {
        AnalyticsService.dailySummary(
            date: day,
            sessions: input.sessions,
            checkIns: input.checkIns,
            cycleEntries: options.includeCycle ? input.cycleEntries : [],
            supportEntries: options.includeSupport ? input.supportEntries : [],
            notes: options.includeNotes ? input.notes : [],
            diaryFactors: input.conditionEvents,
            foodEntries: options.includeFood ? input.foodEntries : [],
            hungerEntries: options.includeFood ? input.hungerEntries : [],
            emotionEntries: input.emotionEntries,
            impulseEntries: input.impulseEntries,
            calendar: calendar
        )
    }

    // MARK: - Markdown

    func markdown() -> String {
        let checkInsByID = Dictionary(input.checkIns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let foodByID = Dictionary(input.foodEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hungerByID = Dictionary(input.hungerEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let range = "\(DateFormatting.fullDate(interval.start)) – \(DateFormatting.fullDate(lastDay))"
        var lines: [String] = []

        if options.includeAIPrompt {
            lines.append(L("Ниже — мой дневник настроения из приложения. Помоги, пожалуйста, заметить закономерности: как менялось настроение и что чаще встречалось в хорошие и в тяжёлые дни. Учитывай, что это самонаблюдения, по некоторым пунктам очень мало записей, а совпадение не означает причину. Не ставь диагнозов.", "Below is my mood diary, exported from an app. Please help me notice patterns: how my mood changed, and what tended to show up on good days versus hard days. Keep in mind these are self-observations, some figures rest on very few entries, and co-occurrence doesn't mean cause. Please don't diagnose."))
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        lines.append("# " + L("Дневник настроения", "Mood diary") + " · " + range)
        lines.append("_" + L("Экспорт из приложения Mood Pomodoro", "Exported from the Mood Pomodoro app") + ", \(DateFormatting.fullDate(now)) \(DateFormatting.time(now)). " + L("Это самонаблюдения, а не медицинские данные.", "These are self-observations, not medical records.") + "_")
        lines.append("")

        lines.append("## " + L("Как читать", "How to read this"))
        let scale = Mood.orderedCases
            .map { "\(Int($0.scale)) \($0.emoji) \($0.label.lowercased())" }
            .joined(separator: ", ")
        lines.append("- " + L("Настроение — шкала от 1 до 5", "Mood is on a 1–5 scale") + ": \(scale).")
        lines.append("- " + L("Check-in — момент, когда я отметила настроение: во время сессии фокуса (по напоминанию таймера) или сама. Среднее настроение дня и периода взвешено по времени: каждая отметка весит столько, сколько длилась (половина промежутка до предыдущей и до следующей отметки, промежуток больше 6 часов считается за 6 часов), поэтому 3 часа на 5 весят больше, чем час частых низких отметок.", "A check-in is a moment when I recorded my mood — either prompted by a timer during a focus session, or on my own. The average mood for a day or period is weighted by time: each check-in counts for as long as it lasted (half the gap to the previous and to the next check-in; gaps over 6 hours count as 6 hours), so 3 hours at 5 weighs more than an hour of frequent low check-ins."))
        lines.append("- " + L("«Записано позже» — запись сделана задним числом; время в начале строки — когда это было на самом деле.", "“Recorded later” means the entry was added afterwards; the time at the start of the line is when it actually happened."))
        if options.includeSupport {
            lines.append("- " + L("Ежедневная поддержка — моя отметка: принято / не принято / не помню. День без отметки значит «не записано», а не «не принято».", "Daily support is my own mark: taken / not taken / don't remember. A day with no mark means it wasn't recorded — not that it wasn't taken."))
        }
        if options.includeFood {
            lines.append("- " + L("Еда — мои собственные пометки для наблюдений: «полезная / обычная / вредная» — это ярлыки на записях, а не оценка меня и не медицинская классификация. Калории и вес еды не считаются. Голод (насколько телу нужна еда) и аппетит (насколько хочется есть) — две разные шкалы 1–5, они не выводятся одна из другой.", "Food entries are my own labels for observation: “wholesome / regular / junk” tag a record, they are not a judgement of me and not a medical classification. Nothing counts calories or portions. Hunger (how much my body needs food) and appetite (how much I feel like eating) are two separate 1–5 scales and neither is derived from the other."))
        }
        lines.append("- " + L("Цифры по нескольким записям ненадёжны, и то, что два события совпали, не значит, что одно вызвало другое.", "Figures based on a handful of entries aren't reliable, and two things happening together doesn't mean one caused the other."))
        lines.append("")

        lines.append("## " + L("Итоги за период", "Summary"))
        lines += summaryLines()
        lines.append("")

        lines.append("## " + L("По дням", "Day by day"))
        var anyDay = false
        for day in days {
            let block = dayBlock(day, checkInsByID: checkInsByID, foodByID: foodByID, hungerByID: hungerByID)
            guard !block.isEmpty else { continue }
            anyDay = true
            lines.append("")
            lines += block
        }
        if !anyDay {
            lines.append("")
            lines.append(L("За этот период записей нет.", "No entries in this period."))
        }
        for sleep in input.manualSleep where sleep.source == .manual && inRange(sleep.day) {
            lines.append("- " + sleep.kind.label + " · " + sleep.start.formatted() + " – " + sleep.end.formatted() + " · " + DurationFormatting.compact(sleep.totalSleep) + (sleep.quality.map { " · " + $0.label } ?? ""))
            if options.includeNotes, let note = sleep.note { lines.append("  " + note) }
        }
        for session in input.sessions where inRange(session.startDate) {
            lines.append("- " + Ldata(session.activity) + " · " + SessionType.label(for: session.sessionType) + " · " + session.startDate.formatted())
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func summaryLines() -> [String] {
        var lines: [String] = []
        let checkIns = input.checkIns.filter { inRange($0.timestamp) }
        let stats = AnalyticsService.moodStatistics(of: checkIns)
        let daysWithMood = Set(checkIns.map { calendar.startOfDay(for: $0.timestamp) }).count

        lines.append("- " + L("Дней в периоде", "Days in period") + ": \(days.count); " + L("с отметками настроения", "with mood entries") + ": \(daysWithMood)")
        if let average = stats.average {
            lines.append("- " + L("Check-in", "Check-ins") + ": \(stats.checkInCount); " + L("среднее настроение", "average mood") + ": " + String(format: "%.1f / 5", average))
            let distribution = Mood.orderedCases.map { mood -> String in
                let share = stats.distribution.percentage(for: mood) ?? 0
                return "\(mood.emoji) \(Int((share * 100).rounded()))%"
            }
            lines.append("- " + L("Распределение", "Distribution") + ": " + distribution.joined(separator: " · "))
        } else {
            lines.append("- " + L("Отметок настроения за период нет.", "No mood check-ins in this period."))
        }

        let sessions = input.sessions.filter { inRange($0.startDate) }
        let activities = AnalyticsService.activityDurationStatistics(sessions: sessions, checkIns: checkIns)
        if !activities.isEmpty {
            let total = activities.reduce(0) { $0 + $1.activeDuration }
            lines.append("- " + L("Время в фокусе", "Focus time") + ": \(DurationFormatting.compact(total)), " + L("сессий", "sessions") + ": \(sessions.count)")
            for activity in activities {
                var line = "  - \(Ldata(activity.activityName)) —\(DurationFormatting.compact(activity.activeDuration)), " + L("сессий", "sessions") + ": \(activity.sessionCount)"
                if let average = activity.averageMood {
                    line += "; " + L("среднее настроение во время", "average mood during") + " " + String(format: "%.1f", average) + " (\(checkInCount(activity.checkInCount)))"
                }
                lines.append(line)
            }
        }

        if options.includeSupport, !input.supportEntries.isEmpty {
            var counts: [SupportStatus: Int] = [:]
            var unmarked = 0
            for day in days {
                if let entry = AnalyticsService.supportEntry(on: day, entries: input.supportEntries, calendar: calendar) {
                    counts[entry.status, default: 0] += 1
                } else {
                    unmarked += 1
                }
            }
            let parts = SupportStatus.allCases.map { "\($0.label.lowercased()) \(counts[$0] ?? 0)" }
                + [L("не отмечено", "not recorded") + " \(unmarked)"]
            lines.append("- " + L("Ежедневная поддержка, дней", "Daily support, days") + ": " + parts.joined(separator: " · "))
        }

        if options.includeFood {
            let meals = input.foodEntries.filter { inRange($0.eventDate) }
            let hunger = input.hungerEntries.filter { !$0.isEmpty && inRange($0.eventDate) }
            if !meals.isEmpty {
                let parts = AnalyticsService.categoryCounts(of: meals)
                    .map { "\($0.category.label.lowercased()) \($0.count)" }
                lines.append("- " + L("Записей о еде", "Food entries") + ": \(meals.count) (" + parts.joined(separator: " · ") + ")")
                let treats = AnalyticsService.treatBreakdown(of: meals)
                if !treats.isEmpty {
                    let byType = treats.byType.map { "\($0.type.label.lowercased()) \($0.count)" }
                    let byAmount = treats.byAmount.map { "\($0.amount.label.lowercased()) \($0.count)" }
                    lines.append("  - " + L("Вредная еда", "Junk / treat") + ": " + (byType + byAmount).joined(separator: " · "))
                }
            }
            if !hunger.isEmpty {
                var parts: [String] = []
                if let average = AnalyticsService.averageScale(hunger.compactMap(\.hunger)) {
                    parts.append(L("средний голод", "average hunger") + " " + String(format: "%.1f / 5", average)
                                 + " (\(hunger.compactMap(\.hunger).count))")
                }
                if let average = AnalyticsService.averageScale(hunger.compactMap(\.appetite)) {
                    parts.append(L("средний аппетит", "average appetite") + " " + String(format: "%.1f / 5", average)
                                 + " (\(hunger.compactMap(\.appetite).count))")
                }
                if !parts.isEmpty {
                    lines.append("- " + L("Голод и аппетит", "Hunger and appetite") + ": " + parts.joined(separator: "; "))
                }
                let before = meals.compactMap {
                    AnalyticsService.hungerEntry(before: $0.eventDate, in: input.hungerEntries)?.hunger
                }
                if let average = AnalyticsService.averageScale(before) {
                    lines.append("  - " + L("Голод перед едой", "Hunger before meals") + ": "
                                 + String(format: "%.1f / 5", average) + " (\(before.count))")
                }
            }
        }

        if options.includeCycle, !input.cycleEntries.isEmpty {
            let periodDays = days.filter { AnalyticsService.isPeriodDay($0, entries: input.cycleEntries, calendar: calendar) }
            if !periodDays.isEmpty {
                lines.append("- " + L("Дни менструации", "Period days") + ": " + periodDays.map(DateFormatting.compactDate).joined(separator: ", "))
            }
        }

        var conditionCounts: [String: Int] = [:]
        for checkIn in checkIns {
            for entry in checkIn.conditionSnapshot {
                conditionCounts["\(Ldata(entry.categoryName)): \(Ldata(entry.optionName))", default: 0] += 1
            }
        }
        for event in input.conditionEvents where event.session == nil && inRange(event.timestamp) {
            conditionCounts["\(Ldata(event.categoryName)): \(Ldata(event.optionName))", default: 0] += 1
        }
        if !conditionCounts.isEmpty {
            let top = conditionCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(8)
                .map { "\($0.key) (\($0.value))" }
            lines.append("- " + L("Чаще всего отмеченные условия", "Most often recorded conditions") + ": " + top.joined(separator: ", "))
        }
        return lines
    }

    private func dayBlock(
        _ day: Date,
        checkInsByID: [UUID: CheckIn],
        foodByID: [UUID: FoodEntry],
        hungerByID: [UUID: HungerEntry]
    ) -> [String] {
        let summary = summary(for: day)
        let hasCycle = options.includeCycle && (summary.isPeriodDay || !summary.cycleEvents.isEmpty)
        guard !summary.isEmpty || hasCycle else { return [] }

        var header = "### " + day.formatted(
            .dateTime.weekday(.wide).day().month(.wide).year().locale(AppLanguage.current.locale)
        )
        if let average = summary.moodStats.average {
            header += " — " + L("среднее", "average") + " " + String(format: "%.1f / 5", average)
                + " (\(checkInCount(summary.moodStats.checkInCount)))"
        }
        var lines = [header]

        if options.includeSupport, let support = summary.support {
            let when = support.time.map(DateFormatting.time) ?? L("в течение дня", "during the day")
            var line = "- 💊 " + L("Ежедневная поддержка", "Daily support") + ": \(support.status.label) · \(when)"
            if options.includeNotes, let note = support.note { line += " — “\(note)”" }
            lines.append(line)
        }
        if options.includeCycle {
            if summary.isPeriodDay {
                let text = summary.cycleDay.map { L("Менструация — день \($0)", "Period — day \($0)") } ?? L("Менструация", "Period")
                lines.append("- 🌸 " + text)
            } else if let cycleDay = summary.cycleDay {
                lines.append("- 🌸 " + L("День цикла: \(cycleDay)", "Cycle day: \(cycleDay)"))
            }
        }
        if !summary.activities.isEmpty {
            let parts = summary.activities.map { "\(Ldata($0.activityName)) \(DurationFormatting.compact($0.activeDuration))" }
            lines.append("- 📚 " + L("Занятия", "Focus") + ": " + parts.joined(separator: ", "))
        }
        if !summary.conditions.isEmpty {
            let parts = summary.conditions.map { "\(Ldata($0.categoryName)): \(Ldata($0.optionName))" }
            lines.append("- ☕ " + L("Условия", "Conditions") + ": " + parts.joined(separator: "; "))
        }
        for event in summary.timelineEvents {
            guard let text = describe(
                event,
                checkInsByID: checkInsByID,
                foodByID: foodByID,
                hungerByID: hungerByID
            ) else { continue }
            lines.append("- \(DateFormatting.time(event.timestamp)) · \(text)")
        }
        return lines
    }

    /// "(записано позже: …)" — the same note the check-in rows carry, so a
    /// backdated entry is never read as something logged in the moment.
    private func recordedLaterSuffix(eventDate: Date, createdAt: Date) -> String {
        guard createdAt.timeIntervalSince(eventDate) > 30 * 60 else { return "" }
        let written = "\(DateFormatting.compactDate(createdAt)) \(DateFormatting.time(createdAt))"
        return " " + L("(записано позже: \(written))", "(recorded later: \(written))")
    }

    private func describe(
        _ event: TimelineEvent,
        checkInsByID: [UUID: CheckIn],
        foodByID: [UUID: FoodEntry],
        hungerByID: [UUID: HungerEntry]
    ) -> String? {
        switch event.kind {
        case .checkIn:
            guard let mood = event.mood else { return nil }
            var text = "\(mood.emoji) \(mood.label) (\(Int(mood.scale))/5)"
            if case .checkIn(let id)? = event.target, let checkIn = checkInsByID[id] {
                if let reason = checkIn.reason { text += " — \(Ldata(reason))" }
                if let energy = checkIn.energy {
                    text += " · " + L("силы", "energy") + ": \(energy.emoji) \(energy.label)"
                }
                if let motivation = checkIn.motivation {
                    text += " · " + L("мотивация", "motivation") + ": \(motivation.emoji) \(motivation.label)"
                    if let why = checkIn.motivationReason { text += " (\(Ldata(why)))" }
                }
                if options.includeNotes, let note = checkIn.note, !note.isEmpty { text += " — “\(note)”" }
                if checkIn.createdAt.timeIntervalSince(checkIn.timestamp) > 30 * 60 {
                    let written = "\(DateFormatting.compactDate(checkIn.createdAt)) \(DateFormatting.time(checkIn.createdAt))"
                    text += " " + L("(записано позже: \(written))", "(recorded later: \(written))")
                }
            }
            return text
        case .food:
            guard options.includeFood, case .food(let id)? = event.target, let entry = foodByID[id] else { return nil }
            var text = "\(entry.category.emoji) \(entry.detailLine)"
            if let desc = entry.desc, !desc.isEmpty { text += " — \(desc)" }
            if let fullness = entry.fullness {
                text += " · " + L("после еды", "afterwards") + ": \(fullness.label)"
            }
            if options.includeNotes, let note = entry.note, !note.isEmpty { text += " — “\(note)”" }
            text += recordedLaterSuffix(eventDate: entry.eventDate, createdAt: entry.createdAt)
            return text
        case .hunger:
            guard options.includeFood, case .hunger(let id)? = event.target, let entry = hungerByID[id] else { return nil }
            var text = "🍎 \(entry.summaryLine)"
            if options.includeNotes, let note = entry.note, !note.isEmpty { text += " — “\(note)”" }
            text += recordedLaterSuffix(eventDate: entry.eventDate, createdAt: entry.createdAt)
            return text
        case .emotion, .impulse:
            return event.title + (options.includeNotes ? event.subtitle.map { " · " + $0 } ?? "" : "")
        case .note:
            return options.includeNotes ? "📝 “\(event.title)”" : nil
        case .support:
            // Already stated on the day's own support line.
            return nil
        case .start, .end, .pause, .resume, .conditionChanged:
            let glyph: String
            switch event.kind {
            case .start, .resume: glyph = "▶︎"
            case .end: glyph = "⏹"
            case .pause: glyph = "🌿"
            default: glyph = "☕"
            }
            var text = "\(glyph) \(event.title)"
            // A backdated activity's subtitle carries its free-text note.
            let isManualNote: Bool
            if case .session? = event.target { isManualNote = true } else { isManualNote = false }
            if let subtitle = event.subtitle, !subtitle.isEmpty, options.includeNotes || !isManualNote {
                text += " (\(subtitle))"
            }
            return text
        }
    }

    // MARK: - JSON

    func json() -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = calendar.timeZone
        iso.formatOptions = [.withInternetDateTime]
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let checkIns = input.checkIns.filter { inRange($0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
        let sessions = input.sessions.filter { inRange($0.startDate) }.sorted { $0.startDate < $1.startDate }

        let export = JSONExport(
            readme: L("Дневник настроения из приложения Mood Pomodoro. Настроение по шкале 1–5 (5 — очень хорошо). Это самонаблюдения, а не медицинские данные; совпадение не означает причину. У отсутствующей отметки поддержки значение «не записано», а не «не принято». time — когда событие произошло, recordedAt — когда его записали. Категории еды (полезная / обычная / вредная) — мои личные ярлыки для наблюдений, не оценка и не медицинская классификация; калории не считаются. Голод и аппетит — две независимые шкалы 1–5.", "Mood diary from the Mood Pomodoro app. Mood is on a 1–5 scale (5 = very good). Self-observations, not medical records; co-occurrence is not causation. A missing daily-support mark means “not recorded”, not “not taken”. `time` is when something happened; `recordedAt` is when it was written down. The food categories (wholesome / regular / junk) are my own labels for observation, not a judgement and not a medical classification; nothing counts calories. Hunger and appetite are two independent 1–5 scales."),
            language: options.language.rawValue,
            exportedAt: iso.string(from: now),
            period: .init(start: dayFormatter.string(from: interval.start), end: dayFormatter.string(from: lastDay)),
            moodScale: Mood.orderedCases.map { .init(value: Int($0.scale), emoji: $0.emoji, label: $0.label) },
            days: days.compactMap { day in
                let summary = summary(for: day)
                guard !summary.isEmpty || summary.isPeriodDay else { return nil }
                return .init(
                    date: dayFormatter.string(from: day),
                    averageMood: summary.moodStats.average.map { ($0 * 10).rounded() / 10 },
                    checkInCount: summary.moodStats.checkInCount,
                    focusMinutes: Int(summary.totalActiveDuration / 60),
                    cycleDay: options.includeCycle ? summary.cycleDay : nil,
                    periodDay: options.includeCycle && summary.isPeriodDay ? true : nil,
                    dailySupport: options.includeSupport ? summary.support?.status.rawValue : nil
                )
            },
            checkIns: checkIns.map { checkIn in
                .init(
                    time: iso.string(from: checkIn.timestamp),
                    recordedAt: iso.string(from: checkIn.createdAt),
                    mood: Int(checkIn.mood.scale),
                    moodLabel: checkIn.mood.label,
                    reason: checkIn.reason.map(Ldata),
                    energy: checkIn.energy.map { Int($0.scale) },
                    energyLabel: checkIn.energy?.label,
                    motivation: checkIn.motivation.map { Int($0.scale) },
                    motivationLabel: checkIn.motivation?.label,
                    motivationReason: checkIn.motivationReason.map(Ldata),
                    note: options.includeNotes ? checkIn.note : nil,
                    source: checkIn.origin == .scheduled ? "timer-prompt" : "manual",
                    activity: checkIn.session.map { Ldata($0.activity) },
                    conditions: checkIn.conditionSnapshot.map { "\(Ldata($0.categoryName)): \(Ldata($0.optionName))" }
                )
            },
            sessions: sessions.map { session in
                .init(
                    activity: Ldata(session.activity),
                    start: iso.string(from: session.startDate),
                    end: session.endDate.map { iso.string(from: $0) },
                    activeMinutes: Int(session.activeWorkDuration() / 60),
                    breakMinutes: Int(session.breakDuration() / 60),
                    enteredManually: session.isManualEntry,
                    note: options.includeNotes ? session.note : nil
                )
            },
            dailySupport: options.includeSupport
                ? days.compactMap { day in
                    guard let entry = AnalyticsService.supportEntry(on: day, entries: input.supportEntries, calendar: calendar) else { return nil }
                    return .init(
                        date: dayFormatter.string(from: day),
                        status: entry.status.rawValue,
                        statusLabel: entry.status.label,
                        time: entry.time.map { timeFormatter.string(from: $0) },
                        note: options.includeNotes ? entry.note : nil
                    )
                }
                : nil,
            cycle: options.includeCycle
                ? input.cycleEntries.filter { inRange($0.date) }.sorted { $0.date < $1.date }.map {
                    .init(date: dayFormatter.string(from: $0.date), mark: $0.kind.rawValue, label: $0.kind.label)
                }
                : nil,
            factors: input.conditionEvents
                .filter { $0.session == nil && inRange($0.timestamp) }
                .sorted { $0.timestamp < $1.timestamp }
                .map { .init(time: iso.string(from: $0.timestamp), category: Ldata($0.categoryName), value: Ldata($0.optionName)) },
            notes: options.includeNotes
                ? input.notes.filter { inRange($0.timestamp) }.sorted { $0.timestamp < $1.timestamp }.map {
                    .init(time: iso.string(from: $0.timestamp), text: $0.text)
                }
                : nil,
            food: options.includeFood
                ? input.foodEntries.filter { inRange($0.eventDate) }.sorted { $0.eventDate < $1.eventDate }.map { entry in
                    .init(
                        time: iso.string(from: entry.eventDate),
                        recordedAt: iso.string(from: entry.createdAt),
                        category: entry.category.rawValue,
                        categoryLabel: entry.category.label,
                        mealDensity: entry.mealDensity?.rawValue,
                        taste: entry.taste?.rawValue,
                        treatType: entry.treatType?.rawValue,
                        treatAmount: entry.treatAmount?.rawValue,
                        fullness: entry.fullness.map { Int($0.scale) },
                        fullnessLabel: entry.fullness?.label,
                        what: entry.desc,
                        note: options.includeNotes ? entry.note : nil,
                        hungerBefore: AnalyticsService
                            .hungerEntry(before: entry.eventDate, in: input.hungerEntries)?
                            .hunger.map { Int($0.scale) }
                    )
                }
                : nil,
            hungerAppetite: options.includeFood
                ? input.hungerEntries
                    .filter { !$0.isEmpty && inRange($0.eventDate) }
                    .sorted { $0.eventDate < $1.eventDate }
                    .map { entry in
                        .init(
                            time: iso.string(from: entry.eventDate),
                            recordedAt: iso.string(from: entry.createdAt),
                            hunger: entry.hunger.map { Int($0.scale) },
                            hungerLabel: entry.hunger?.label,
                            appetite: entry.appetite.map { Int($0.scale) },
                            appetiteLabel: entry.appetite?.label,
                            note: options.includeNotes ? entry.note : nil
                        )
                    }
                : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(export),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "{}" }
        object["emotions"] = input.emotionEntries.filter { !$0.isEmpty && inRange($0.eventDate) }.map { entry -> [String: Any] in
            var row: [String: Any] = ["id": entry.id.uuidString, "time": iso.string(from: entry.eventDate), "recordedAt": iso.string(from: entry.createdAt), "emotions": entry.emotions.map(\.rawValue)]
            if options.includeNotes { row["note"] = entry.note }
            return row
        }
        object["impulses"] = input.impulseEntries.filter { inRange($0.eventDate) }.map { entry -> [String: Any] in
            var row: [String: Any] = ["id": entry.id.uuidString, "time": iso.string(from: entry.eventDate), "recordedAt": iso.string(from: entry.createdAt), "category": entry.category.rawValue]
            row["strength"] = entry.strength?.scale
            row["outcome"] = entry.outcome?.rawValue
            if options.includeNotes { row["note"] = entry.note }
            return row
        }
        object["manualSleep"] = input.manualSleep.filter { $0.source == .manual && inRange($0.day) }.map { sleep -> [String: Any] in
            var row: [String: Any] = ["start": iso.string(from: sleep.start), "end": iso.string(from: sleep.end), "kind": sleep.kind.rawValue, "durationSeconds": sleep.totalSleep, "excludedFromTotals": sleep.isSuperseded]
            row["quality"] = sleep.quality?.rawValue
            if options.includeNotes { row["note"] = sleep.note }
            return row
        }
        if var rows = object["sessions"] as? [[String: Any]] {
            for index in rows.indices { rows[index]["type"] = sessions[index].sessionType?.rawValue }
            object["sessions"] = rows
        }
        guard let result = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: result, encoding: .utf8) else { return "{}" }
        return text + "\n"
    }
}

/// JSON shape. Keys are English and stable whatever the language; the
/// human-readable values (labels, names) follow the export language.
private struct JSONExport: Encodable {
    struct Period: Encodable { let start: String; let end: String }
    struct ScalePoint: Encodable { let value: Int; let emoji: String; let label: String }
    struct Day: Encodable {
        let date: String
        let averageMood: Double?
        let checkInCount: Int
        let focusMinutes: Int
        let cycleDay: Int?
        let periodDay: Bool?
        let dailySupport: String?
    }
    struct CheckInRecord: Encodable {
        let time: String
        let recordedAt: String
        let mood: Int
        let moodLabel: String
        let reason: String?
        /// Nil where that scale wasn't answered — "не отмечено" is not the
        /// middle of the scale, and the export must not imply it was.
        let energy: Int?
        let energyLabel: String?
        let motivation: Int?
        let motivationLabel: String?
        let motivationReason: String?
        let note: String?
        let source: String
        let activity: String?
        let conditions: [String]
    }
    struct SessionRecord: Encodable {
        let activity: String
        let start: String
        let end: String?
        let activeMinutes: Int
        let breakMinutes: Int
        let enteredManually: Bool
        let note: String?
    }
    struct SupportRecord: Encodable {
        let date: String
        let status: String
        let statusLabel: String
        let time: String?
        let note: String?
    }
    struct CycleRecord: Encodable { let date: String; let mark: String; let label: String }
    struct FactorRecord: Encodable { let time: String; let category: String; let value: String }
    struct NoteRecord: Encodable { let time: String; let text: String }
    /// A meal as recorded. Only the fields belonging to its category are
    /// present — a treat has no density or taste, a meal has no amount.
    struct FoodRecord: Encodable {
        let time: String
        let recordedAt: String
        let category: String
        let categoryLabel: String
        let mealDensity: String?
        let taste: String?
        let treatType: String?
        let treatAmount: String?
        let fullness: Int?
        let fullnessLabel: String?
        let what: String?
        let note: String?
        /// Hunger recorded shortly *before* this meal, when there was one.
        /// Proximity in time only — it says nothing about cause.
        let hungerBefore: Int?
    }
    /// Kept apart on purpose: nil means that scale wasn't answered, which
    /// is not the same as the middle of it.
    struct HungerRecord: Encodable {
        let time: String
        let recordedAt: String
        let hunger: Int?
        let hungerLabel: String?
        let appetite: Int?
        let appetiteLabel: String?
        let note: String?
    }

    let readme: String
    var app = "Mood Pomodoro"
    let language: String
    let exportedAt: String
    let period: Period
    let moodScale: [ScalePoint]
    let days: [Day]
    let checkIns: [CheckInRecord]
    let sessions: [SessionRecord]
    let dailySupport: [SupportRecord]?
    let cycle: [CycleRecord]?
    let factors: [FactorRecord]
    let notes: [NoteRecord]?
    let food: [FoodRecord]?
    let hungerAppetite: [HungerRecord]?

    init(
        readme: String,
        language: String,
        exportedAt: String,
        period: Period,
        moodScale: [ScalePoint],
        days: [Day],
        checkIns: [CheckInRecord],
        sessions: [SessionRecord],
        dailySupport: [SupportRecord]?,
        cycle: [CycleRecord]?,
        factors: [FactorRecord],
        notes: [NoteRecord]?,
        food: [FoodRecord]?,
        hungerAppetite: [HungerRecord]?
    ) {
        self.readme = readme
        self.language = language
        self.exportedAt = exportedAt
        self.period = period
        self.moodScale = moodScale
        self.days = days
        self.checkIns = checkIns
        self.sessions = sessions
        self.dailySupport = dailySupport
        self.cycle = cycle
        self.factors = factors
        self.notes = notes
        self.food = food
        self.hungerAppetite = hungerAppetite
    }
}
