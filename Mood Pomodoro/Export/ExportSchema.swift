import Foundation

/// Canonical export document. JSON keys are stable English; localized
/// labels live beside raw values. `schemaVersion` 2 replaced the mixed
/// Encodable + `[String: Any]` file.
struct MoodPomodoroExport: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var app: String
    var exportedAt: String
    var timezone: String
    var locale: String
    var requestedPeriod: ExportPeriod
    var privacy: ExportPrivacy
    var definitions: ExportDefinitions
    var summary: ExportPeriodSummary
    var days: [ExportDay]
    var checkIns: [ExportCheckIn]
    var emotions: [ExportEmotionEntry]
    var hungerAppetite: [ExportHungerEntry]
    var food: [ExportFoodEntry]
    var impulses: [ExportImpulseEntry]
    var sessions: [ExportSession]
    var standaloneConditions: [ExportConditionEvent]
    var supportEntries: [ExportSupportEntry]
    var healthMedicationDays: [ExportHealthMedicationDay]
    var cycleEntries: [ExportCycleEntry]
    var healthCycleMarks: [ExportHealthCycleMark]
    var notes: [ExportNote]
    var sleep: [ExportSleep]
}

struct ExportPeriod: Codable, Equatable, Sendable {
    var start: String
    var end: String
    var startInstant: String
    var endExclusive: String
    var dayCount: Int
}

struct ExportPrivacy: Codable, Equatable, Sendable {
    var includeNotes: Bool
    var includeCycle: Bool
    var includeSupport: Bool
    var includeFood: Bool
    var includeHealth: Bool
    var excludedByToggles: [String]
    var notes: [String]
}

struct ExportDefinitions: Codable, Equatable, Sendable {
    var mood: [ExportScaleValue]
    var energy: [ExportScaleValue]
    var motivation: [ExportScaleValue]
    var hunger: [ExportScaleValue]
    var appetite: [ExportScaleValue]
    var fullness: [ExportScaleValue]
    var sleepQuality: [ExportScaleValue]
    var impulseStrength: [ExportScaleValue]
    var emotions: [ExportEmotionDef]
    var foodCategories: [ExportLabeled]
    var impulseCategories: [ExportLabeled]
    var impulseOutcomes: [ExportLabeled]
    var supportStatuses: [ExportLabeled]
    var cycleEventKinds: [ExportLabeled]
    var sessionTypes: [ExportLabeled]
    var sessionStates: [ExportLabeled]
    var sleepKinds: [ExportLabeled]
    var sleepStages: [ExportLabeled]
    var rules: [String]
}

struct ExportScaleValue: Codable, Equatable, Sendable {
    var raw: String
    var value: Int
    var label: String
    var emoji: String
}

struct ExportLabeled: Codable, Equatable, Sendable {
    var raw: String
    var label: String
    var emoji: String?
    var glyph: String?
}

struct ExportEmotionDef: Codable, Equatable, Sendable {
    var raw: String
    var label: String
    var emoji: String
    var colorHex: String
}

struct ExportDayScale: Codable, Equatable, Sendable {
    var average: Double
    var observationCount: Int
    var method: String
}

struct ExportDayEventIDs: Codable, Equatable, Sendable {
    var checkIns: [String]
    var emotions: [String]
    var hungerAppetite: [String]
    var food: [String]
    var impulses: [String]
    var sessions: [String]
    var sleep: [String]
    var notes: [String]
    var standaloneConditions: [String]
}

struct ExportDaySleep: Codable, Equatable, Sendable {
    var durationSeconds: Double
    var sessionIds: [String]
}

struct ExportDaySupport: Codable, Equatable, Sendable {
    var status: String
    var statusLabel: String
    var glyph: String?
    var source: String?
    var entryId: String?
    var time: String?
    var note: String?
    var takenCount: Int?
    var skippedCount: Int?
}

struct ExportDay: Codable, Equatable, Sendable {
    var date: String
    var hasData: Bool
    var mood: ExportDayScale?
    var energy: ExportDayScale?
    var motivation: ExportDayScale?
    var hunger: ExportDayScale?
    var appetite: ExportDayScale?
    var emotions: [ExportLabeled]
    var emotionEntryCount: Int
    var mealsByCategory: [String: Int]
    var mealCount: Int
    var impulseCount: Int
    var impulsesByCategory: [String: Int]
    var impulsesByOutcome: [String: Int]
    var impulsesByStrength: [String: Int]
    var nightSleep: ExportDaySleep?
    var napSleep: ExportDaySleep?
    var sleepQuality: ExportScaleValue?
    var cycleDay: Int?
    var isPeriodDay: Bool
    var cycleSource: String?
    var menstrualFlow: ExportLabeled?
    var isCycleStart: Bool?
    var support: ExportDaySupport
    var sessionDurationByTypeSeconds: [String: Double]
    var sessionCountByType: [String: Int]
    var activeDurationSeconds: Double
    var breakDurationSeconds: Double
    var conditions: [ExportConditionRef]
    var noteIds: [String]
    var eventIds: ExportDayEventIDs
}

struct ExportConditionRef: Codable, Equatable, Sendable {
    var categoryId: String
    var categoryRaw: String
    var optionId: String
    var optionRaw: String
    var icon: String?
    var iconImageName: String?
}

struct ExportCheckIn: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var mood: ExportScaleValue
    var energy: ExportScaleValue?
    var motivation: ExportScaleValue?
    var moodReason: String?
    var motivationReason: String?
    var note: String?
    var origin: String
    var scheduledAt: String?
    var sourceIdentifier: String?
    var occurrenceId: String?
    var sessionId: String?
    var sessionActivity: String?
    var sessionType: ExportLabeled?
    var conditionSnapshot: [ExportConditionRef]
}

struct ExportEmotionEntry: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var emotions: [ExportEmotionDef]
    var note: String?
}

struct ExportHungerEntry: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var hunger: ExportScaleValue?
    var appetite: ExportScaleValue?
    var note: String?
}

struct ExportFoodEntry: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var category: ExportLabeled
    var description: String?
    var mealDensity: ExportLabeled?
    var taste: ExportLabeled?
    var treatType: ExportLabeled?
    var treatAmount: ExportLabeled?
    var fullness: ExportScaleValue?
    var note: String?
    var hungerBefore: ExportScaleValue?
    var hungerBeforeSeconds: Double?
    var hungerBeforeId: String?
}

struct ExportImpulseEntry: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var category: ExportLabeled
    var strength: ExportScaleValue?
    var outcome: ExportLabeled?
    var note: String?
}

struct ExportSegment: Codable, Equatable, Sendable {
    var id: String
    var type: String
    var start: String
    var end: String?
    var durationSeconds: Double
    var durationWithinRequestedPeriodSeconds: Double
}

struct ExportConditionEvent: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var categoryId: String
    var categoryRaw: String
    var optionId: String
    var optionRaw: String
    var icon: String?
    var iconImageName: String?
    var sessionId: String?
}

struct ExportSession: Codable, Equatable, Sendable {
    var id: String
    var state: String
    var activity: String
    var type: ExportLabeled
    var start: String
    var end: String?
    var calculatedThrough: String?
    var overlapDurationSeconds: Double
    var activeDurationSeconds: Double
    var breakDurationSeconds: Double
    var totalDurationSeconds: Double
    var breakCount: Int
    var origin: String
    var checkInIntervalMinutes: Int
    var note: String?
    var recordedAt: String
    var updatedAt: String
    var segments: [ExportSegment]
    var conditionChanges: [ExportConditionEvent]
    var checkInIds: [String]
}

struct ExportSupportEntry: Codable, Equatable, Sendable {
    var id: String
    var trackerKey: String
    var day: String
    var time: String?
    var status: ExportLabeled
    var note: String?
    var recordedAt: String
    var updatedAt: String
    var source: String
}

struct ExportHealthMedicationDay: Codable, Equatable, Sendable {
    var day: String
    var takenCount: Int
    var skippedCount: Int
    var status: ExportLabeled?
    var detail: String?
    var sourceName: String?
}

struct ExportCycleEntry: Codable, Equatable, Sendable {
    var id: String
    var day: String
    var kind: ExportLabeled
    var note: String?
    var recordedAt: String
    var updatedAt: String
}

struct ExportHealthCycleMark: Codable, Equatable, Sendable {
    var day: String
    var kind: ExportLabeled
    var flow: ExportLabeled?
    var isCycleStart: Bool
    var sourceName: String?
}

struct ExportNote: Codable, Equatable, Sendable {
    var id: String
    var eventTime: String
    var recordedAt: String
    var updatedAt: String
    var text: String
}

struct ExportSleepInterval: Codable, Equatable, Sendable {
    var stage: String
    var stageLabel: String
    var start: String
    var end: String
    var durationSeconds: Double
}

struct ExportSleep: Codable, Equatable, Sendable {
    var id: String
    var day: String
    var kind: ExportLabeled
    var source: String
    var start: String
    var end: String
    var totalSleepSeconds: Double
    var timeInBedSeconds: Double?
    var awakeDurationSeconds: Double
    var coreDurationSeconds: Double
    var deepDurationSeconds: Double
    var remDurationSeconds: Double
    var unspecifiedDurationSeconds: Double
    var awakeningCount: Int?
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var productType: String?
    var subjectiveQuality: ExportScaleValue?
    var note: String?
    var isSuperseded: Bool
    var supersededBy: String?
    var countedInTotals: Bool
    var intervals: [ExportSleepInterval]
}

struct ExportCountedAverage: Codable, Equatable, Sendable {
    var average: Double?
    var dayCount: Int
    var observationCount: Int
    var method: String
}

struct ExportPeriodSummary: Codable, Equatable, Sendable {
    var periodDays: Int
    var emptyDays: Int
    var daysWithMood: Int
    var daysWithSleep: Int
    var daysWithFood: Int
    var daysWithEmotions: Int
    var daysWithImpulses: Int
    var daysWithSessions: Int
    var daysWithPeriod: Int
    var checkInCount: Int
    var emotionEntryCount: Int
    var hungerEntryCount: Int
    var foodCount: Int
    var impulseCount: Int
    var sessionCount: Int
    var sleepCount: Int
    var noteCount: Int
    var mood: ExportCountedAverage
    var energy: ExportCountedAverage
    var motivation: ExportCountedAverage
    var hunger: ExportCountedAverage
    var appetite: ExportCountedAverage
    var nightSleepSeconds: Double
    var napSleepSeconds: Double
    var activeDurationSeconds: Double
    var breakDurationSeconds: Double
    var supportDaysByStatus: [String: Int]
    var mealsByCategory: [String: Int]
    var emotionsByRaw: [String: Int]
    var impulsesByCategory: [String: Int]
    var sessionsByType: [String: Int]
    var sessionsByActivity: [String: Int]
    var sleepStagesSeconds: [String: Double]
}
