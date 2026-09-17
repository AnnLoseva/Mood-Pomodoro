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
        case .hunger: return L("Голод", "Hunger")
        case .appetite: return L("Аппетит", "Appetite")
        case .sleep: return L("Сон", "Sleep")
        case .activity: return L("Занятия", "Activities")
        case .emotion: return L("Эмоции", "Emotions")
        case .food: return L("Еда", "Food")
        case .impulse: return L("Импульсы", "Impulses")
        case .context: return L("Таблетки и цикл", "Medication and cycle")
        }
    }

    var color: Color {
        switch self {
        case .mood: return DayScaleMetric.mood.color
        case .energy: return DayScaleMetric.energy.color
        case .motivation: return DayScaleMetric.motivation.color
        case .hunger: return DayScaleMetric.hunger.color
        case .appetite: return DayScaleMetric.appetite.color
        case .sleep: return Color(red: 0.32, green: 0.40, blue: 0.55)
        case .activity: return AppTheme.forest
        case .emotion: return Color(red: 0.494, green: 0.376, blue: 0.604)
        case .food: return AppTheme.moss
        case .impulse: return AppTheme.rust
        case .context: return Color(red: 0.541, green: 0.455, blue: 0.349)
        }
    }

    var textColor: Color {
        switch self {
        case .mood: return AppTheme.forestDeep
        case .energy: return Color(red: 0.541, green: 0.416, blue: 0.031)
        case .motivation: return Color(red: 0.588, green: 0.161, blue: 0.122)
        case .hunger: return Color(red: 0.173, green: 0.396, blue: 0.380)
        case .appetite: return Color(red: 0.588, green: 0.282, blue: 0.165)
        case .sleep: return Color(red: 0.235, green: 0.298, blue: 0.431)
        case .activity: return AppTheme.forestDeep
        case .emotion: return Color(red: 0.373, green: 0.275, blue: 0.463)
        case .food: return Color(red: 0.353, green: 0.404, blue: 0.251)
        case .impulse: return AppTheme.rustDeep
        case .context: return Color(red: 0.420, green: 0.345, blue: 0.251)
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
    static let defaultOn: Set<String> = ["mood", "sleep", "food"]
}

enum TimelineSpan: String, CaseIterable, Identifiable, Sendable {
    case day, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return L("День", "Day")
        case .week: return L("Неделя", "Week")
        case .month: return L("Месяц", "Month")
        }
    }
    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

/// Caption pieces stored without localized strings so a locale change can
/// re-resolve titles without walking SwiftData again.
enum TimelineCaption: Sendable, Hashable {
    case scale(layer: TimelineLayer, value: Int)
    case food(FoodCategory)
    case emotion(Emotion)
    case impulse(category: ImpulseCategory, extra: String)
    case sleep(kind: SleepKind, duration: TimeInterval, qualityLabel: String?)
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
    let numericGroups: [TimelineLayer: [[TimelineMark]]]
    let contextDays: [DayAggregate]

    static let empty = TimelineSnapshot(
        intervalStart: .distantPast,
        intervalEnd: .distantPast,
        marks: [],
        numericGroups: [:],
        contextDays: []
    )

    var isEmpty: Bool { marks.isEmpty && contextDays.isEmpty }
}

enum TimelineSnapshotBuilder {
    static let connectGap: TimeInterval = 90 * 60

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

    static func build(facts: TimelineFacts, contextDays: [DayAggregate] = []) -> TimelineSnapshot {
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
                    marks.append(TimelineMark(
                        id: "h\(entry.id.uuidString)",
                        date: entry.eventDate,
                        layer: .hunger,
                        value: hunger.scale,
                        target: .hunger(entry.id),
                        caption: .scale(layer: .hunger, value: Int(hunger.scale))
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

            var groups: [TimelineLayer: [[TimelineMark]]] = [:]
            for layer in TimelineLayer.numericLayers {
                groups[layer] = numericGroups(marks.filter { $0.layer == layer && $0.value != nil })
            }

            return TimelineSnapshot(
                intervalStart: facts.intervalStart,
                intervalEnd: facts.intervalEnd,
                marks: marks,
                numericGroups: groups,
                contextDays: contextDays
            )
        }
    }

    static func numericGroups(_ points: [TimelineMark]) -> [[TimelineMark]] {
        let pts = points.sorted { $0.date < $1.date }
        var out: [[TimelineMark]] = []
        var current: [TimelineMark] = []
        for (index, point) in pts.enumerated() {
            if index > 0, point.date.timeIntervalSince(pts[index - 1].date) > connectGap {
                out.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

enum DiaryPeriodInterval {
    /// Visible diary/chart window.
    static func visible(for date: Date, span: TimelineSpan, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: span.calendarComponent, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 3600)
    }

    /// Fetch window: events in the visible interval, sessions/sleep that may
    /// have started the evening before.
    static func fetch(for date: Date, span: TimelineSpan, calendar: Calendar = .current) -> DateInterval {
        let visible = visible(for: date, span: span, calendar: calendar)
        let pad: TimeInterval = span == .day ? 36 * 3600 : 12 * 3600
        return DateInterval(start: visible.start.addingTimeInterval(-pad), end: visible.end)
    }

    /// Cycle day needs a start recorded before the visible window.
    static func cycleFetch(for date: Date, span: TimelineSpan, calendar: Calendar = .current) -> DateInterval {
        let visible = visible(for: date, span: span, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -400, to: visible.start) ?? visible.start
        return DateInterval(start: start, end: visible.end)
    }
}
