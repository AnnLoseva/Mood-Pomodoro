import Foundation

struct AnalyticsDayRow: Identifiable, Sendable {
    var id: Date { day }
    var day: Date
    var mood: Double?
    var moodCount: Int
    var energy: Double?
    var energyCount: Int
    var motivation: Double?
    var motivationCount: Int
    var hunger: Double?
    var hungerCount: Int
    var appetite: Double?
    var appetiteCount: Int
    var sleepSeconds: TimeInterval?
    var napSeconds: TimeInterval
    var sleepQuality: Double?
    var awakeningCount: Int?
    var bedtime: Date?
    var wakeTime: Date?
    var deepSeconds: TimeInterval?
    var remSeconds: TimeInterval?
    var coreSeconds: TimeInterval?
    var totalStagedSleep: TimeInterval?
    var isPeriodDay: Bool
    var cycleDay: Int?
    var supportRaw: String?
    var mealCount: Int
    var treatCount: Int
    var emotions: Set<String>
    var impulseCount: Int
    var impulseCategories: Set<String>
    var factorKeys: Set<String>
    var durationByType: [String: TimeInterval]
    var sessionCount: Int
    var hasFood: Bool { mealCount > 0 }
    var hasNap: Bool { napSeconds > 0 }

    func value(_ key: String) -> Double? {
        switch key {
        case "mood": return mood
        case "energy": return energy
        case "motivation": return motivation
        case "hunger": return hunger
        case "appetite": return appetite
        case "sleep": return sleepSeconds.map { $0 / 3600 }
        case "rest": return durationByType[SessionType.rest.rawValue].map { $0 / 3600 }
        case "work": return durationByType[SessionType.obligatoryWork.rawValue].map { $0 / 3600 }
        case "study": return durationByType[SessionType.study.rawValue].map { $0 / 3600 }
        default: return nil
        }
    }
}

struct AnalyticsDelta: Sendable {
    var key: String
    var title: String
    var current: Double
    var previous: Double
    var difference: Double
    var currentDays: Int
    var previousDays: Int
    var confidence: AnalyticsConfidence
}

struct AnalyticsOverview: Sendable {
    var periodLabel: String
    var periodStart: Date
    var periodEndExclusive: Date
    var dayCount: Int
    var daysWithData: Int
    var coverage: Double
    var mood: AnalyticsScaleAverage
    var energy: AnalyticsScaleAverage
    var motivation: AnalyticsScaleAverage
    var hunger: AnalyticsScaleAverage
    var appetite: AnalyticsScaleAverage
    var checkInCount: Int
    var sessionCount: Int
    var nightCount: Int
    var mealCount: Int
    var emotionDayCount: Int
    var impulseDayCount: Int
    var periodDayCount: Int
    var supportTakenDays: Int
    var supportSkippedDays: Int
    var restSeconds: TimeInterval
    var workSeconds: TimeInterval
    var studySeconds: TimeInterval
    var untypedSeconds: TimeInterval
    var averageSleepSeconds: TimeInterval?
    var deltas: [AnalyticsDelta]
}

struct AnalyticsWeekPoint: Identifiable, Sendable {
    var id: Date { weekStart }
    var weekStart: Date
    var seconds: TimeInterval
    var sessionCount: Int
}

struct AnalyticsActivityRow: Identifiable, Sendable {
    var id: String
    var name: String
    var typeRaw: String?
    var sessionCount: Int
    var dayCount: Int
    var totalSeconds: TimeInterval
    var averageSeconds: TimeInterval
    var mood: AnalyticsScaleAverage
    var energy: AnalyticsScaleAverage
    var motivation: AnalyticsScaleAverage
    var moodBefore: AnalyticsScaleAverage
    var moodDuring: AnalyticsScaleAverage
    var moodAfter: AnalyticsScaleAverage
    var moodDelta: Double?
    var weekly: [AnalyticsWeekPoint]
    var confidence: AnalyticsConfidence
}

struct AnalyticsFactorRow: Identifiable, Sendable {
    var id: String
    var categoryID: UUID
    var optionID: UUID
    var categoryName: String
    var optionName: String
    var icon: String
    var iconImageName: String?
    var categoryEnabled: Bool
    var dayCount: Int
    var sessionCount: Int
    var observationCount: Int
    var mood: AnalyticsScaleAverage
    var energy: AnalyticsScaleAverage
    var motivation: AnalyticsScaleAverage
    var moodDelta: Double?
    var minutesToDifficult: Double?
    var neededForPreliminary: Int
    var confidence: AnalyticsConfidence
}

struct AnalyticsReasonRow: Identifiable, Sendable {
    var id: String { moodRaw + "|" + reason }
    var moodRaw: String
    var reason: String
    var count: Int
    var moodTotal: Int
    var answeredTotal: Int
    var percentageOfAnswered: Double
}

struct AnalyticsFoodCategoryRow: Identifiable, Sendable {
    var id: String
    var label: String
    var count: Int
    var moodAfter: AnalyticsScaleAverage
    var hungerBefore: AnalyticsScaleAverage
}

struct AnalyticsFoodSummary: Sendable {
    var mealCount: Int
    var hungerFilledShare: Double?
    var appetiteFilledShare: Double?
    var fullnessFilledShare: Double?
    var moodBefore: AnalyticsScaleAverage
    var moodAfter: AnalyticsScaleAverage
    var hungerBefore: AnalyticsScaleAverage
    var fullnessAfter: AnalyticsScaleAverage
    var treatsPerDay: Double?
    var snacksPerDay: Double?
    var impulseFoodDays: Int
    var byCategory: [AnalyticsFoodCategoryRow]
    var hungerAppetitePairs: [AnalyticsGridCell]
    var linkWindowSeconds: TimeInterval
}

struct AnalyticsLabeledCount: Identifiable, Sendable {
    var id: String
    var label: String
    var count: Int
}

struct AnalyticsGridCell: Identifiable, Sendable {
    var id: String { hungerKey + "|" + appetiteKey }
    var hungerKey: String
    var appetiteKey: String
    var count: Int
}

struct AnalyticsSleepSummary: Sendable {
    var nightCount: Int
    var averageSeconds: TimeInterval?
    var medianSeconds: TimeInterval?
    var shortestSeconds: TimeInterval?
    var longestSeconds: TimeInterval?
    var averageQuality: Double?
    var averageAwakenings: Double?
    var napCount: Int
    var averageNapSeconds: TimeInterval?
    var bedtimeSpreadSeconds: TimeInterval?
    var wakeSpreadSeconds: TimeInterval?
    var averageDeepSeconds: TimeInterval?
    var averageDeepShare: Double?
    var averageREMSeconds: TimeInterval?
    var averageCoreSeconds: TimeInterval?
    var stagedNightCount: Int
    var previousAverageSeconds: TimeInterval?
    var previousNightCount: Int
    var moodAfter: [AnalyticsSleepBucket]
    var cycleBuckets: [AnalyticsSleepBucket]
}

struct AnalyticsSleepBucket: Identifiable, Sendable {
    var id: String
    var label: String
    var nightCount: Int
    var mood: AnalyticsScaleAverage
    var energy: AnalyticsScaleAverage
    var appetite: AnalyticsScaleAverage
}

struct AnalyticsEmotionRow: Identifiable, Sendable {
    var id: String
    var raw: String
    var dayCount: Int
    var entryCount: Int
    var mood: AnalyticsScaleAverage
    var energy: AnalyticsScaleAverage
    var motivation: AnalyticsScaleAverage
    var previousNightSleep: TimeInterval?
    var cooccurrence: [AnalyticsLabeledCount]
}

struct AnalyticsImpulseRow: Identifiable, Sendable {
    var id: String
    var categoryRaw: String
    var dayCount: Int
    var entryCount: Int
    var mood: AnalyticsScaleAverage
    var energy: AnalyticsScaleAverage
    var motivation: AnalyticsScaleAverage
    var previousNightSleep: TimeInterval?
    var periodDayCount: Int
    var supportTakenDays: Int
}

struct AnalyticsCompareGroup: Identifiable, Sendable {
    var id: String
    var label: String
    var dayCount: Int
    var observationCount: Int
    var average: Double?
    var confidence: AnalyticsConfidence
}

struct AnalyticsSnapshot: Sendable {
    var builtAt: Date
    var interval: DateInterval
    var days: [AnalyticsDayRow]
    var overview: AnalyticsOverview
    var activities: [AnalyticsActivityRow]
    var factors: [AnalyticsFactorRow]
    var reasons: [AnalyticsReasonRow]
    var food: AnalyticsFoodSummary
    var sleep: AnalyticsSleepSummary
    var emotions: [AnalyticsEmotionRow]
    var impulses: [AnalyticsImpulseRow]
    var trajectory: [MoodTimelinePoint]
    var declineNote: String?

    static let empty = AnalyticsSnapshot(
        builtAt: .distantPast,
        interval: DateInterval(start: .distantPast, end: .distantPast),
        days: [],
        overview: AnalyticsOverview(
            periodLabel: "", periodStart: .distantPast, periodEndExclusive: .distantPast,
            dayCount: 0, daysWithData: 0, coverage: 0,
            mood: .empty, energy: .empty, motivation: .empty, hunger: .empty, appetite: .empty,
            checkInCount: 0, sessionCount: 0, nightCount: 0, mealCount: 0,
            emotionDayCount: 0, impulseDayCount: 0, periodDayCount: 0,
            supportTakenDays: 0, supportSkippedDays: 0,
            restSeconds: 0, workSeconds: 0, studySeconds: 0, untypedSeconds: 0,
            averageSleepSeconds: nil, deltas: []
        ),
        activities: [],
        factors: [],
        reasons: [],
        food: AnalyticsFoodSummary(
            mealCount: 0, hungerFilledShare: nil, appetiteFilledShare: nil, fullnessFilledShare: nil,
            moodBefore: .empty, moodAfter: .empty, hungerBefore: .empty, fullnessAfter: .empty,
            treatsPerDay: nil, snacksPerDay: nil, impulseFoodDays: 0,
            byCategory: [], hungerAppetitePairs: [],
            linkWindowSeconds: AnalyticsService.mealLinkWindow
        ),
        sleep: AnalyticsSleepSummary(
            nightCount: 0, averageSeconds: nil, medianSeconds: nil, shortestSeconds: nil, longestSeconds: nil,
            averageQuality: nil, averageAwakenings: nil, napCount: 0, averageNapSeconds: nil,
            bedtimeSpreadSeconds: nil, wakeSpreadSeconds: nil, averageDeepSeconds: nil, averageDeepShare: nil,
            averageREMSeconds: nil, averageCoreSeconds: nil,
            stagedNightCount: 0, previousAverageSeconds: nil, previousNightCount: 0,
            moodAfter: [], cycleBuckets: []
        ),
        emotions: [],
        impulses: [],
        trajectory: [],
        declineNote: nil
    )
}
