//
//  SleepModels.swift
//  Mood Pomodoro
//

import Foundation

/// Value types for sleep. Deliberately free of HealthKit imports so the
/// aggregation rules below them can be tested without a device, a store or
/// an authorization prompt — `HealthKitSleepService` is the only file that
/// knows `HKCategorySample` exists.
///
/// Nothing here is a medical record or a judgement. The app shows what was
/// recorded and never scores a night, names a disorder, or tells the user
/// how she should sleep.

/// One stretch of one stage, exactly as HealthKit recorded it.
///
/// `inBed` is kept apart from every asleep stage on purpose: it usually
/// *spans* them, and adding it to a sleep total is the single easiest way
/// to report nine hours of sleep for a seven-hour night.
enum SleepStage: String, Codable, Sendable, CaseIterable, Identifiable {
    case inBed
    case awake
    case rem
    case core
    case deep
    /// `asleepUnspecified`, plus the pre-iOS-16 `asleep` value, which is all
    /// an iPhone (or an older watchOS) writes.
    case unspecified

    var id: String { rawValue }

    /// The stages that count toward time asleep. `inBed` and `awake` do not.
    var isAsleep: Bool {
        switch self {
        case .rem, .core, .deep, .unspecified: return true
        case .inBed, .awake: return false
        }
    }

    /// Which stage wins where two overlap, so a minute is never counted
    /// twice and the answer doesn't depend on sample order. More specific
    /// beats less specific; `unspecified` is the weakest asleep value
    /// because it only means "asleep, no detail".
    var precedence: Int {
        switch self {
        case .awake: return 5
        case .deep: return 4
        case .rem: return 3
        case .core: return 2
        case .unspecified: return 1
        case .inBed: return 0
        }
    }

    var label: String {
        switch self {
        case .inBed: return L("В постели", "In bed")
        case .awake: return L("Бодрствование", "Awake")
        case .rem: return L("REM", "REM")
        case .core: return L("Основной", "Core")
        case .deep: return L("Глубокий", "Deep")
        case .unspecified: return L("Сон", "Asleep")
        }
    }

    /// Order used by the stage bar and every legend, deepest at the bottom.
    static var displayOrder: [SleepStage] { [.awake, .rem, .core, .deep, .unspecified] }
}

/// One stage over one stretch of time. Half-open: `[start, end)`.
struct SleepInterval: Hashable, Sendable {
    let stage: SleepStage
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var isEmpty: Bool { end <= start }

    func clamped(to range: ClosedRange<Date>) -> SleepInterval? {
        let clippedStart = Swift.max(start, range.lowerBound)
        let clippedEnd = Swift.min(end, range.upperBound)
        guard clippedEnd > clippedStart else { return nil }
        return SleepInterval(stage: stage, start: clippedStart, end: clippedEnd)
    }
}

/// Night or nap. A presentation heuristic drawn from when the sleep
/// happened and how long it lasted — never a clinical classification, and
/// never used to tell the user she slept wrong.
enum SleepKind: String, Codable, Sendable {
    case night
    case nap

    var label: String {
        switch self {
        case .night: return L("Ночной сон", "Night sleep")
        case .nap: return L("Дневной сон", "Nap")
        }
    }

    var emoji: String {
        switch self {
        case .night: return "🌙"
        case .nap: return "😴"
        }
    }
}

/// How the night felt, in the user's own judgement. Five steps, entirely
/// optional, and **never computed**: a long night can feel awful and a short
/// one fine, so this cannot be derived from duration, from stages, or from
/// anything else the watch recorded. It is her answer, kept beside the
/// measurements rather than mixed into them, and a re-import never touches
/// it.
enum SleepQuality: String, ScaleStep {
    case veryGood
    case good
    case okay
    case bad
    case veryBad

    var id: String { rawValue }

    static var orderedCases: [SleepQuality] { [.veryGood, .good, .okay, .bad, .veryBad] }

    var scale: Double {
        switch self {
        case .veryGood: return 5
        case .good: return 4
        case .okay: return 3
        case .bad: return 2
        case .veryBad: return 1
        }
    }

    var label: String {
        switch self {
        case .veryGood: return L("Очень хорошо", "Very good")
        case .good: return L("Хорошо", "Good")
        case .okay: return L("Нормально", "Okay")
        case .bad: return L("Плохо", "Bad")
        case .veryBad: return L("Очень плохо", "Very bad")
        }
    }

    /// Moon phases again, like `EnergyLevel` — a face here would read as a
    /// mood, which this is not.
    var emoji: String {
        switch self {
        case .veryGood: return "🌕"
        case .good: return "🌔"
        case .okay: return "🌓"
        case .bad: return "🌒"
        case .veryBad: return "🌑"
        }
    }
}

/// Where a session's numbers came from. Kept on every record so the UI can
/// say it plainly and so a HealthKit re-import never silently overwrites
/// something the user typed herself.
enum SleepSource: String, Codable, Sendable {
    case healthKit
    case manual

    var label: String {
        switch self {
        case .healthKit: return L("Apple Health", "Apple Health")
        case .manual: return L("Добавлено вручную", "Added by hand")
        }
    }
}

/// One logical sleep — a night or a nap — after overlapping HealthKit
/// samples have been resolved.
///
/// `totalSleep` is the measure of the *union* of asleep stages with awake
/// stretches removed, so it can never exceed `end - start` and never
/// double-counts a minute that several samples claimed. `timeInBed` is
/// reported separately and is never added to it.
struct SleepSessionSummary: Identifiable, Hashable, Sendable {
    /// Stable across re-imports of the same night: derived from the
    /// session's own bounds, so HealthKit stays the source of truth and an
    /// updated night replaces its old summary instead of adding a second.
    let id: String
    /// The calendar day this sleep is *about* — the day the user woke up.
    /// A night from 23:45 on the 15th to 08:10 on the 16th belongs to the
    /// 16th, which is the day she then lived.
    let day: Date
    let kind: SleepKind
    let source: SleepSource
    let start: Date
    let end: Date
    let totalSleep: TimeInterval
    let timeInBed: TimeInterval?
    let awake: TimeInterval
    let stageDurations: [SleepStage: TimeInterval]
    /// Non-nil only when the stages were detailed enough to count them.
    let awakeningCount: Int?
    /// Resolved, overlap-free intervals, oldest first — what the stage bar
    /// draws. Empty for a manual entry, which has no stages at all.
    let intervals: [SleepInterval]
    /// What wrote the samples, as HealthKit described it. Shown as-is; the
    /// app never claims to know it was an Apple Watch unless HealthKit said
    /// so itself.
    let sourceName: String?
    let sourceBundleIdentifier: String?
    let productType: String?
    /// The user's own answer about this night, if she gave one. Survives
    /// every re-import — see `SleepRecord.apply`.
    var quality: SleepQuality? = nil
    /// True when another record already covers this stretch of the clock
    /// and won it — see `SleepAggregationService.resolveOverlaps(sessions:)`.
    /// Such a session is still shown (so nothing silently disappears) but is
    /// never added to a total.
    var isSuperseded: Bool = false
    /// What is covering it, for the one line the UI shows. Nil unless
    /// `isSuperseded`.
    var supersededBy: SleepSource? = nil
    /// Free-text note from a record the user typed or annotated herself.
    var note: String? = nil

    func duration(of stage: SleepStage) -> TimeInterval { stageDurations[stage] ?? 0 }

    /// True when HealthKit gave real stages rather than a single
    /// undifferentiated "asleep" block — what an Apple Watch night looks
    /// like, and what makes the stage bar worth drawing.
    var hasStageDetail: Bool {
        [.core, .deep, .rem].contains { duration(of: $0) > 0 }
    }

    /// "23:48 → 08:16"
    var timeRange: String { "\(DateFormatting.time(start)) → \(DateFormatting.time(end))" }
}

/// One day's sleep as the diary shows it: the night, any naps, and the sum.
///
/// `sessions` holds everything filed under the day, superseded records
/// included, so the card can still show a HealthKit night the user replaced
/// by hand. Every *total* below counts only `countedSessions` — the
/// overlap-free set — so one night can never be reported twice.
struct SleepDaySummary: Sendable {
    let day: Date
    let sessions: [SleepSessionSummary]

    static func empty(_ day: Date) -> SleepDaySummary { SleepDaySummary(day: day, sessions: []) }

    var isEmpty: Bool { sessions.isEmpty }

    /// What the day's figures are built from: everything that wasn't
    /// overridden by an overlapping record.
    var countedSessions: [SleepSessionSummary] { sessions.filter { !$0.isSuperseded } }
    var supersededSessions: [SleepSessionSummary] { sessions.filter(\.isSuperseded) }

    var night: SleepSessionSummary? { countedSessions.first { $0.kind == .night } }
    var naps: [SleepSessionSummary] { countedSessions.filter { $0.kind == .nap } }

    /// Night plus naps. Counted sessions never overlap each other, so this
    /// is a plain sum rather than another union.
    var totalSleep: TimeInterval { countedSessions.reduce(0) { $0 + $1.totalSleep } }
    var napTotal: TimeInterval { naps.reduce(0) { $0 + $1.totalSleep } }

    /// The day's subjective answer: the night's, or — if only naps were
    /// rated — the first rating there is. Never averaged across sleeps and
    /// never invented.
    var quality: SleepQuality? {
        night?.quality ?? countedSessions.compactMap(\.quality).first
    }

    /// The night's own stage split, which is the only one worth drawing; a
    /// twenty-minute nap's stages say very little.
    var stageDurations: [SleepStage: TimeInterval] { night?.stageDurations ?? [:] }
}
