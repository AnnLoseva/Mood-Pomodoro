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
}

struct ExportInput {
    var sessions: [FocusSession] = []
    var checkIns: [CheckIn] = []
    var cycleEntries: [CycleEntry] = []
    var supportEntries: [SupportEntry] = []
    var notes: [JournalNote] = []
    var conditionEvents: [ConditionEvent] = []

    /// When anything was first recorded — where "all time" starts.
    var earliestDate: Date? {
        let dates = sessions.map(\.startDate) + checkIns.map(\.timestamp) + cycleEntries.map(\.date)
            + supportEntries.map(\.day) + notes.map(\.timestamp) + conditionEvents.map(\.timestamp)
        return dates.min()
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
            calendar: calendar
        )
    }

    // MARK: - Markdown

    func markdown() -> String {
        let checkInsByID = Dictionary(input.checkIns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        lines.append("- " + L("Check-in — момент, когда я отметила настроение: во время сессии фокуса (по напоминанию таймера) или сама. Средние — это среднее по таким отметкам.", "A check-in is a moment when I recorded my mood — either prompted by a timer during a focus session, or on my own. Averages are over those check-ins."))
        lines.append("- " + L("«Записано позже» — запись сделана задним числом; время в начале строки — когда это было на самом деле.", "“Recorded later” means the entry was added afterwards; the time at the start of the line is when it actually happened."))
        if options.includeSupport {
            lines.append("- " + L("Ежедневная поддержка — моя отметка: принято / не принято / не помню. День без отметки значит «не записано», а не «не принято».", "Daily support is my own mark: taken / not taken / don't remember. A day with no mark means it wasn't recorded — not that it wasn't taken."))
        }
        lines.append("- " + L("Цифры по нескольким записям ненадёжны, и то, что два события совпали, не значит, что одно вызвало другое.", "Figures based on a handful of entries aren't reliable, and two things happening together doesn't mean one caused the other."))
        lines.append("")

        lines.append("## " + L("Итоги за период", "Summary"))
        lines += summaryLines()
        lines.append("")

        lines.append("## " + L("По дням", "Day by day"))
        var anyDay = false
        for day in days {
            let block = dayBlock(day, checkInsByID: checkInsByID)
            guard !block.isEmpty else { continue }
            anyDay = true
            lines.append("")
            lines += block
        }
        if !anyDay {
            lines.append("")
            lines.append(L("За этот период записей нет.", "No entries in this period."))
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

    private func dayBlock(_ day: Date, checkInsByID: [UUID: CheckIn]) -> [String] {
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
            guard let text = describe(event, checkInsByID: checkInsByID) else { continue }
            lines.append("- \(DateFormatting.time(event.timestamp)) · \(text)")
        }
        return lines
    }

    private func describe(_ event: TimelineEvent, checkInsByID: [UUID: CheckIn]) -> String? {
        switch event.kind {
        case .checkIn:
            guard let mood = event.mood else { return nil }
            var text = "\(mood.emoji) \(mood.label) (\(Int(mood.scale))/5)"
            if case .checkIn(let id)? = event.target, let checkIn = checkInsByID[id] {
                if let reason = checkIn.reason { text += " — \(Ldata(reason))" }
                if options.includeNotes, let note = checkIn.note, !note.isEmpty { text += " — “\(note)”" }
                if checkIn.createdAt.timeIntervalSince(checkIn.timestamp) > 30 * 60 {
                    let written = "\(DateFormatting.compactDate(checkIn.createdAt)) \(DateFormatting.time(checkIn.createdAt))"
                    text += " " + L("(записано позже: \(written))", "(recorded later: \(written))")
                }
            }
            return text
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
            readme: L("Дневник настроения из приложения Mood Pomodoro. Настроение по шкале 1–5 (5 — очень хорошо). Это самонаблюдения, а не медицинские данные; совпадение не означает причину. У отсутствующей отметки поддержки значение «не записано», а не «не принято». time — когда событие произошло, recordedAt — когда его записали.", "Mood diary from the Mood Pomodoro app. Mood is on a 1–5 scale (5 = very good). Self-observations, not medical records; co-occurrence is not causation. A missing daily-support mark means “not recorded”, not “not taken”. `time` is when something happened; `recordedAt` is when it was written down."),
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
                : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(export), let text = String(data: data, encoding: .utf8) else { return "{}" }
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
        notes: [NoteRecord]?
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
    }
}
