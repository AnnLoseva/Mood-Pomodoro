import Foundation
import SwiftUI

/// Layers on the unified diary plot. Shared by the snapshot builder and the
/// view so pan/zoom can filter a prepared set instead of walking SwiftData.
enum TimelineLayer: String, CaseIterable, Identifiable, Sendable, Hashable {
    case mood, energy, motivation, hunger, appetite
    case sleep, activity
    case emotion, food, impulse
    case context

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: return L("Настроение", "Mood")
        case .energy: return L("Энергия", "Energy")
        case .motivation: return L("Мотивация", "Motivation")
        case .hunger: return L("Сытость", "Satiety")
        case .appetite: return L("Аппетит", "Appetite")
        case .sleep: return L("Сон", "Sleep")
        case .activity: return L("Занятия", "Activities")
        case .emotion: return L("Эмоции", "Emotions")
        case .food: return L("Еда", "Food")
        case .impulse: return L("Импульсы", "Impulses")
        case .context: return L("Дневной контекст", "Day context")
        }
    }

    /// The series colour, shared with the analytics charts
    /// (`AnalyticsPalette`). Marks that carry their own meaning (emotion,
    /// food, impulse) keep their colours.
    var color: Color {
        switch self {
        case .mood: return AnalyticsPalette.mood.color
        case .energy: return AnalyticsPalette.energy.color
        case .motivation: return AnalyticsPalette.motivation.color
        case .hunger: return AnalyticsPalette.hunger.color
        case .appetite: return AnalyticsPalette.appetite.color
        case .sleep: return AnalyticsPalette.sleep.color
        case .activity: return AnalyticsPalette.activity.color
        case .emotion: return Color(red: 0.494, green: 0.376, blue: 0.604)
        case .food: return AppTheme.moss
        case .impulse: return AppTheme.rust
        case .context: return Color(red: 0.541, green: 0.455, blue: 0.349)
        }
    }

    /// The same hue, dark enough for text.
    var textColor: Color {
        switch self {
        case .mood: return AnalyticsPalette.text(AnalyticsPalette.mood).color
        case .energy: return AnalyticsPalette.text(AnalyticsPalette.energy).color
        case .motivation: return AnalyticsPalette.text(AnalyticsPalette.motivation).color
        case .hunger: return AnalyticsPalette.text(AnalyticsPalette.hunger).color
        case .appetite: return AnalyticsPalette.text(AnalyticsPalette.appetite).color
        case .sleep: return AnalyticsPalette.text(AnalyticsPalette.sleep).color
        case .activity: return AnalyticsPalette.text(AnalyticsPalette.activity).color
        case .emotion: return Color(red: 0.373, green: 0.275, blue: 0.463)
        case .food: return Color(red: 0.353, green: 0.404, blue: 0.251)
        case .impulse: return AppTheme.rustDeep
        case .context: return Color(red: 0.420, green: 0.345, blue: 0.251)
        }
    }

    /// Lines vs. marks and intervals — the two groups the chart's controls
    /// keep apart. Sleep lives with the marks even where a week or month
    /// draws it as a line of hours.
    enum Group: Sendable { case line, mark }

    var group: Group { isNumeric ? .line : .mark }

    /// How a line's points are drawn, so two lines never differ by colour alone.
    var shape: SeriesShape {
        switch self {
        case .mood: return .circle
        case .energy: return .square
        case .motivation: return .triangle
        case .hunger: return .diamond
        case .appetite: return .plus
        default: return .circle
        }
    }

    /// Glyph for a mark or interval chip.
    var markSymbol: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .activity: return "leaf.fill"
        case .emotion: return "sparkles"
        case .food: return "fork.knife"
        case .impulse: return "bolt.fill"
        case .context: return "pills.fill"
        default: return "circle.fill"
        }
    }

    var isNumeric: Bool {
        switch self {
        case .mood, .energy, .motivation, .hunger, .appetite: return true
        default: return false
        }
    }

    var isInterval: Bool { self == .sleep || self == .activity }
    var isEvent: Bool { self == .emotion || self == .food || self == .impulse }

    var eventRowFraction: Double {
        switch self {
        case .emotion: return 0.2
        case .food: return 0.5
        case .impulse: return 0.8
        default: return 0.5
        }
    }

    static let numericLayers: [TimelineLayer] = [.mood, .energy, .motivation, .hunger, .appetite]
    static let lineLayers: [TimelineLayer] = numericLayers
    static let markLayers: [TimelineLayer] = [.sleep, .activity, .emotion, .food, .impulse, .context]
    static let defaultOn: Set<String> = Set(TimelineLayerSelection.defaultRaw.split(separator: ",").map(String.init))
}

enum TimelineSpan: String, CaseIterable, Identifiable, Sendable {
    case day, week, month
    /// Everything ever recorded, up to today.
    case all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return L("День", "Day")
        case .week: return L("Неделя", "Week")
        case .month: return L("Месяц", "Month")
        case .all: return L("Всё время", "All time")
        }
    }
    /// Nil for `.all`, which is not a calendar unit — its start is wherever
    /// the first record is.
    var calendarComponent: Calendar.Component? {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .all: return nil
        }
    }
}

/// Caption pieces stored without localized strings so a locale change can
/// re-resolve titles without walking SwiftData again.
enum TimelineCaption: Sendable, Hashable {
    case scale(layer: TimelineLayer, value: Int)
    case dailyAverage(layer: TimelineLayer, value: Double)
    case food(FoodCategory)
    case emotion(Emotion)
    case impulse(category: ImpulseCategory, extra: String)
    case sleep(kind: SleepKind, duration: TimeInterval, qualityLabel: String?)
    /// Everything slept on one calendar day — night and naps together.
    case sleepDay(duration: TimeInterval)
    case activity(name: String, type: SessionType?)
}

/// One mark on the shared clock. Identifiers are derived from the source
/// record, never from a fresh UUID.
struct TimelineMark: Identifiable, Sendable, Hashable {
    let id: String
    let date: Date
    var end: Date?
    let layer: TimelineLayer
    var value: Double?
    var target: DiaryEditTarget?
    var art: String?
    var caption: TimelineCaption
    var sessionType: SessionType?
    var foodCategory: FoodCategory?
    var emotion: Emotion?
    var sleepKind: SleepKind?

    var eventPosition: Double { layer.eventRowFraction }

    var title: String {
        switch caption {
        case .scale(let layer, let value):
            return layer.title + " · \(value)/5"
        case .dailyAverage(let layer, let value):
            return layer.title + " · " + L("среднее за день", "daily average") + " " + String(format: "%.1f", value)
        case .food(let category):
            return "\(category.emoji) \(category.label)"
        case .emotion(let emotion):
            return "\(emotion.emoji) \(emotion.label)"
        case .impulse(let category, let extra):
            return extra.isEmpty
                ? "\(category.emoji) \(category.label)"
                : "\(category.emoji) \(category.label) · \(extra)"
        case .sleep(let kind, let duration, let quality):
            var text = kind.emoji + " " + kind.label + " · " + DurationFormatting.compact(duration)
            if let quality { text += " · " + quality }
            return text
        case .sleepDay(let duration):
            return "😴 " + L("Сон за день", "Sleep that day") + " · " + DurationFormatting.compact(duration)
        case .activity(let name, let type):
            return Ldata(name) + " · " + SessionType.label(for: type)
        }
    }

    var color: Color {
        switch layer {
        case .activity:
            return SessionType.color(for: sessionType)
        case .food:
            switch foodCategory {
            case .healthy: return AppTheme.moss
            case .regular: return AppTheme.forest
            case .treat: return AppTheme.rust
            case .none: return layer.color
            }
        case .emotion:
            return emotion?.color ?? layer.color
        case .sleep:
            return sleepKind == .night
                ? Color(red: 0.32, green: 0.40, blue: 0.55)
                : Color(red: 0.55, green: 0.62, blue: 0.45)
        default:
            return layer.color
        }
    }
}

/// Plain values copied off SwiftData models. Safe to send across actors.
struct TimelineFacts: Sendable {
    struct CheckInFact: Sendable {
        let id: UUID
        let timestamp: Date
        let mood: Mood
        let energy: EnergyLevel?
        let motivation: StudyMotivation?
    }

    struct HungerFact: Sendable {
        let id: UUID
        let eventDate: Date
        let hunger: HungerLevel?
        let appetite: AppetiteLevel?
    }

    struct FoodFact: Sendable {
        let id: UUID
        let eventDate: Date
        let category: FoodCategory
    }

    struct EmotionFact: Sendable {
        let id: UUID
        let eventDate: Date
        let emotions: [Emotion]
    }

    struct ImpulseFact: Sendable {
        let id: UUID
        let eventDate: Date
        let category: ImpulseCategory
        let extra: String
    }

    struct ActivityFact: Sendable {
        let segmentID: UUID
        let sessionID: UUID
        let start: Date
        let end: Date
        let activity: String
        let type: SessionType?
    }

    let intervalStart: Date
    let intervalEnd: Date
    let now: Date
    let checkIns: [CheckInFact]
    let hunger: [HungerFact]
    let food: [FoodFact]
    let emotions: [EmotionFact]
    let impulses: [ImpulseFact]
    let sleep: [SleepSessionSummary]
    let activities: [ActivityFact]
}

struct TimelineSnapshot: Sendable {
    let intervalStart: Date
    let intervalEnd: Date
    let marks: [TimelineMark]
    /// Every recorded value, joined into lines. Week and month never break
    /// a line; a day breaks it only across a night's sleep.
    let numericGroups: [TimelineLayer: [[TimelineMark]]]
    /// One mark per day that has records, holding that day's average over
    /// time (not over check-ins). Empty for a day span.
    let dailyAverages: [TimelineLayer: [TimelineMark]]
    /// One mark per day with any sleep on it, valued in hours, night and
    /// naps together. Empty for a day span, which draws the sleeps themselves.
    let sleepDays: [TimelineMark]
    let contextDays: [DayAggregate]

    static let empty = TimelineSnapshot(
        intervalStart: .distantPast,
        intervalEnd: .distantPast,
        marks: [],
        numericGroups: [:],
        dailyAverages: [:],
        sleepDays: [],
        contextDays: []
    )

    var isEmpty: Bool { marks.isEmpty && contextDays.isEmpty }
}

enum TimelineSnapshotBuilder {
    static func capture(
        interval: DateInterval,
        checkIns: [CheckIn],
        hunger: [HungerEntry],
        food: [FoodEntry],
        emotions: [EmotionEntry],
        impulses: [ImpulseEntry],
        sessions: [FocusSession],
        sleep: [SleepSessionSummary],
        now: Date = .now
    ) -> TimelineFacts {
        let start = interval.start
        let end = interval.end
        func within(_ date: Date) -> Bool { date >= start && date < end }
        func overlaps(_ a: Date, _ b: Date) -> Bool { a < end && b > start }

        let activityFacts: [TimelineFacts.ActivityFact] = sessions.flatMap { session in
            (session.segments ?? []).compactMap { segment in
                guard segment.type == .work else { return nil }
                let segmentEnd = segment.endDate ?? now
                guard overlaps(segment.startDate, segmentEnd) else { return nil }
                return TimelineFacts.ActivityFact(
                    segmentID: segment.id,
                    sessionID: session.id,
                    start: segment.startDate,
                    end: segmentEnd,
                    activity: session.activity,
                    type: session.sessionType
                )
            }
        }

        return TimelineFacts(
            intervalStart: start,
            intervalEnd: end,
            now: now,
            checkIns: checkIns.filter { within($0.timestamp) }.map {
                TimelineFacts.CheckInFact(id: $0.id, timestamp: $0.timestamp, mood: $0.mood, energy: $0.energy, motivation: $0.motivation)
            },
            hunger: hunger.filter { within($0.eventDate) }.map {
                TimelineFacts.HungerFact(id: $0.id, eventDate: $0.eventDate, hunger: $0.hunger, appetite: $0.appetite)
            },
            food: food.filter { within($0.eventDate) }.map {
                TimelineFacts.FoodFact(id: $0.id, eventDate: $0.eventDate, category: $0.category)
            },
            emotions: emotions.filter { within($0.eventDate) && !$0.isEmpty }.map {
                TimelineFacts.EmotionFact(id: $0.id, eventDate: $0.eventDate, emotions: $0.emotions)
            },
            impulses: impulses.filter { within($0.eventDate) }.map {
                TimelineFacts.ImpulseFact(id: $0.id, eventDate: $0.eventDate, category: $0.category, extra: $0.detailLine)
            },
            sleep: sleep.filter { !$0.isSuperseded && overlaps($0.start, $0.end) },
            activities: activityFacts
        )
    }

    static func build(
        facts: TimelineFacts,
        span: TimelineSpan,
        contextDays: [DayAggregate] = [],
        calendar: Calendar = .current
    ) -> TimelineSnapshot {
        PerfSignpost.interval("timeline.snapshot") {
            var marks: [TimelineMark] = []
            marks.reserveCapacity(
                facts.checkIns.count * 3
                    + facts.hunger.count * 2
                    + facts.food.count
                    + facts.emotions.count
                    + facts.impulses.count
                    + facts.sleep.count
                    + facts.activities.count
            )

            for entry in facts.checkIns {
                marks.append(TimelineMark(
                    id: "\(entry.id.uuidString)-mood",
                    date: entry.timestamp,
                    layer: .mood,
                    value: entry.mood.scale,
                    target: .checkIn(entry.id),
                    caption: .scale(layer: .mood, value: Int(entry.mood.scale))
                ))
                if let energy = entry.energy {
                    marks.append(TimelineMark(
                        id: "\(entry.id.uuidString)-energy",
                        date: entry.timestamp,
                        layer: .energy,
                        value: energy.scale,
                        target: .checkIn(entry.id),
                        caption: .scale(layer: .energy, value: Int(energy.scale))
                    ))
                }
                if let motivation = entry.motivation {
                    marks.append(TimelineMark(
                        id: "\(entry.id.uuidString)-motivation",
                        date: entry.timestamp,
                        layer: .motivation,
                        value: motivation.scale,
                        target: .checkIn(entry.id),
                        caption: .scale(layer: .motivation, value: Int(motivation.scale))
                    ))
                }
            }

            for entry in facts.hunger {
                if let hunger = entry.hunger {
                    // Drawn inverted, as satiety: the higher the line, the
                    // fuller the body, not the hungrier.
                    let satiety = 6 - hunger.scale
                    marks.append(TimelineMark(
                        id: "h\(entry.id.uuidString)",
                        date: entry.eventDate,
                        layer: .hunger,
                        value: satiety,
                        target: .hunger(entry.id),
                        caption: .scale(layer: .hunger, value: Int(satiety))
                    ))
                }
                if let appetite = entry.appetite {
                    marks.append(TimelineMark(
                        id: "a\(entry.id.uuidString)",
                        date: entry.eventDate,
                        layer: .appetite,
                        value: appetite.scale,
                        target: .hunger(entry.id),
                        caption: .scale(layer: .appetite, value: Int(appetite.scale))
                    ))
                }
            }

            for entry in facts.food {
                marks.append(TimelineMark(
                    id: "food-\(entry.id.uuidString)",
                    date: entry.eventDate,
                    layer: .food,
                    target: .food(entry.id),
                    art: entry.category.imageName,
                    caption: .food(entry.category),
                    foodCategory: entry.category
                ))
            }

            for entry in facts.emotions {
                for emotion in entry.emotions {
                    marks.append(TimelineMark(
                        id: "\(entry.id.uuidString)-\(emotion.rawValue)",
                        date: entry.eventDate,
                        layer: .emotion,
                        target: .emotion(entry.id),
                        art: emotion.imageName,
                        caption: .emotion(emotion),
                        emotion: emotion
                    ))
                }
            }

            for entry in facts.impulses {
                marks.append(TimelineMark(
                    id: "imp-\(entry.id.uuidString)",
                    date: entry.eventDate,
                    layer: .impulse,
                    target: .impulse(entry.id),
                    caption: .impulse(category: entry.category, extra: entry.extra)
                ))
            }

            for entry in facts.sleep {
                marks.append(TimelineMark(
                    id: "sleep-\(entry.id)",
                    date: entry.start,
                    end: entry.end,
                    layer: .sleep,
                    target: .sleep(entry.id),
                    caption: .sleep(kind: entry.kind, duration: entry.totalSleep, qualityLabel: entry.quality?.label),
                    sleepKind: entry.kind
                ))
            }

            for entry in facts.activities {
                marks.append(TimelineMark(
                    id: "seg-\(entry.segmentID.uuidString)",
                    date: entry.start,
                    end: entry.end,
                    layer: .activity,
                    target: .session(entry.sessionID),
                    caption: .activity(name: entry.activity, type: entry.type),
                    sessionType: entry.type
                ))
            }

            marks.sort { $0.date < $1.date }

            // A line is broken only by a night's sleep, and only in the day
            // view: that is where a new day starts. A longer window never
            // breaks — a quiet hour, or a quiet day, is not a new line.
            let nightSleeps = span == .day
                ? facts.sleep.filter { $0.kind == .night }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                : []

            var groups: [TimelineLayer: [[TimelineMark]]] = [:]
            var averages: [TimelineLayer: [TimelineMark]] = [:]
            for layer in TimelineLayer.numericLayers {
                let points = marks.filter { $0.layer == layer && $0.value != nil }
                groups[layer] = numericGroups(points, breakingAt: nightSleeps)
                if span != .day {
                    averages[layer] = dailyAverages(points, layer: layer, calendar: calendar)
                }
            }

            return TimelineSnapshot(
                intervalStart: facts.intervalStart,
                intervalEnd: facts.intervalEnd,
                marks: marks,
                numericGroups: groups,
                dailyAverages: averages,
                sleepDays: span == .day
                    ? []
                    : sleepDays(facts.sleep, in: DateInterval(start: facts.intervalStart, end: facts.intervalEnd), calendar: calendar),
                contextDays: contextDays
            )
        }
    }

    /// Sleep per calendar day for the week and month lines: every night and
    /// nap filed under a day is added up, so the line answers "how much did
    /// I sleep that day". A night belongs to the day it ended on. Days
    /// without a record get no mark — the line runs through them.
    static func sleepDays(_ sleep: [SleepSessionSummary], in interval: DateInterval, calendar: Calendar = .current) -> [TimelineMark] {
        var byDay: [Date: [SleepSessionSummary]] = [:]
        for session in sleep {
            let day = calendar.startOfDay(for: session.day)
            guard day >= interval.start, day < interval.end else { continue }
            byDay[day, default: []].append(session)
        }
        return byDay.keys.sorted().compactMap { day in
            guard let sessions = byDay[day],
                  let longest = sessions.max(by: { $0.totalSleep < $1.totalSleep }),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let total = sessions.reduce(0) { $0 + $1.totalSleep }
            guard total > 0 else { return nil }
            return TimelineMark(
                id: "sleepday-\(Int(day.timeIntervalSince1970))",
                date: day.addingTimeInterval(next.timeIntervalSince(day) / 2),
                layer: .sleep,
                value: total / 3600,
                target: .sleep(longest.id),
                caption: .sleepDay(duration: total)
            )
        }
    }

    /// Joins points into lines. Points are connected however far apart they
    /// are; a line starts anew only where one of `breaks` lies between two
    /// neighbours (or the neighbour sits inside it).
    static func numericGroups(_ points: [TimelineMark], breakingAt breaks: [DateInterval] = []) -> [[TimelineMark]] {
        let pts = points.sorted { $0.date < $1.date }
        var out: [[TimelineMark]] = []
        var current: [TimelineMark] = []
        for (index, point) in pts.enumerated() {
            if index > 0, breaks.contains(where: { $0.start < point.date && $0.end > pts[index - 1].date }) {
                out.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// One mark per calendar day that holds a record of `layer`, set at the
    /// middle of the day. Each value is the mean of the line over the hours
    /// of that day — the same straight-line path the chart draws between
    /// records — so a day with twenty check-ins in one morning weighs the
    /// morning by its length, not by its count. Hours before the first record
    /// and after the last are not on the line and are left out of the mean.
    static func dailyAverages(_ points: [TimelineMark], layer: TimelineLayer, calendar: Calendar = .current) -> [TimelineMark] {
        let pts = points.filter { $0.value != nil }.sorted { $0.date < $1.date }
        guard !pts.isEmpty else { return [] }

        var area: [Date: Double] = [:]
        var seconds: [Date: TimeInterval] = [:]
        for (a, b) in zip(pts, pts.dropFirst()) {
            let span = b.date.timeIntervalSince(a.date)
            guard span > 0, let va = a.value, let vb = b.value else { continue }
            var day = calendar.startOfDay(for: a.date)
            while day < b.date {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let lo = max(a.date, day)
                let hi = min(b.date, next)
                if hi > lo {
                    let v0 = va + (vb - va) * lo.timeIntervalSince(a.date) / span
                    let v1 = va + (vb - va) * hi.timeIntervalSince(a.date) / span
                    let length = hi.timeIntervalSince(lo)
                    area[day, default: 0] += (v0 + v1) / 2 * length
                    seconds[day, default: 0] += length
                }
                day = next
            }
        }

        var recorded: [Date: [Double]] = [:]
        for point in pts {
            if let value = point.value { recorded[calendar.startOfDay(for: point.date), default: []].append(value) }
        }

        return recorded.keys.sorted().compactMap { day in
            let value: Double
            if let length = seconds[day], length > 0 {
                value = (area[day] ?? 0) / length
            } else if let values = recorded[day], !values.isEmpty {
                // A lone record has no stretch of line to weigh.
                value = values.reduce(0, +) / Double(values.count)
            } else {
                return nil
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return TimelineMark(
                id: "avg-\(layer.rawValue)-\(Int(day.timeIntervalSince1970))",
                date: day.addingTimeInterval(next.timeIntervalSince(day) / 2),
                layer: layer,
                value: value,
                caption: .dailyAverage(layer: layer, value: value)
            )
        }
    }
}

enum DiaryPeriodInterval {
    /// Visible diary/chart window.
    static func visible(for date: Date, span: TimelineSpan, calendar: Calendar = .current) -> DateInterval {
        guard let component = span.calendarComponent else {
            // All time: the real start is the earliest record, which only
            // the caller has seen. Reading from the beginning of time to the
            // end of today fetches everything.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
            return DateInterval(start: .distantPast, end: tomorrow)
        }
        return calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 3600)
    }

    /// Fetch window: events in the visible interval, sessions/sleep that may
    /// have started the evening before.
    static func fetch(for date: Date, span: TimelineSpan, calendar: Calendar = .current) -> DateInterval {
        let visible = visible(for: date, span: span, calendar: calendar)
        if span == .all { return visible }
        let pad: TimeInterval = span == .day ? 36 * 3600 : 12 * 3600
        return DateInterval(start: visible.start.addingTimeInterval(-pad), end: visible.end)
    }

    /// Cycle day needs a start recorded before the visible window.
    static func cycleFetch(for date: Date, span: TimelineSpan, calendar: Calendar = .current) -> DateInterval {
        let visible = visible(for: date, span: span, calendar: calendar)
        if span == .all { return visible }
        let start = calendar.date(byAdding: .day, value: -400, to: visible.start) ?? visible.start
        return DateInterval(start: start, end: visible.end)
    }
}
