import Foundation

struct AnalyticsConditionFact: Hashable, Sendable {
    var categoryID: UUID
    var optionID: UUID
    var categoryName: String
    var optionName: String
    var icon: String
    var iconImageName: String?
    var categoryEnabled: Bool
}

struct AnalyticsCheckInFact: Sendable {
    var id: UUID
    var timestamp: Date
    var mood: Double
    var moodRaw: String
    var energy: Double?
    var motivation: Double?
    var reason: String?
    var sessionID: UUID?
    var conditions: [AnalyticsConditionFact]
}

struct AnalyticsSessionFact: Sendable {
    var id: UUID
    var activity: String
    var typeRaw: String?
    var start: Date
    var end: Date?
    var stateRaw: String
    var activeDuration: TimeInterval
    var breakDuration: TimeInterval
    var checkInIDs: [UUID]
}

struct AnalyticsConditionEventFact: Sendable {
    var id: UUID
    var timestamp: Date
    var categoryID: UUID
    var optionID: UUID
    var sessionID: UUID?
}

struct AnalyticsHungerFact: Sendable {
    var id: UUID
    var eventDate: Date
    var hunger: Double?
    var appetite: Double?
}

struct AnalyticsFoodFact: Sendable {
    var id: UUID
    var eventDate: Date
    var categoryRaw: String
    var fullness: Double?
}

struct AnalyticsEmotionFact: Sendable {
    var id: UUID
    var eventDate: Date
    var emotions: [String]
}

struct AnalyticsImpulseFact: Sendable {
    var id: UUID
    var eventDate: Date
    var categoryRaw: String
    var outcomeRaw: String?
}

struct AnalyticsSupportFact: Sendable {
    var id: UUID
    var day: Date
    var statusRaw: String
}

struct AnalyticsCycleFact: Sendable {
    var day: Date
    var kindRaw: String
    var sourceRaw: String
}

struct AnalyticsCategoryFact: Sendable {
    var id: UUID
    var name: String
    var icon: String
    var iconImageName: String?
    var isEnabled: Bool
    var options: [AnalyticsOptionFact]
}

struct AnalyticsOptionFact: Sendable {
    var id: UUID
    var name: String
    var icon: String
    var iconImageName: String?
}

struct AnalyticsFacts: Sendable {
    var checkIns: [AnalyticsCheckInFact]
    var sessions: [AnalyticsSessionFact]
    var conditionEvents: [AnalyticsConditionEventFact]
    var hunger: [AnalyticsHungerFact]
    var food: [AnalyticsFoodFact]
    var emotions: [AnalyticsEmotionFact]
    var impulses: [AnalyticsImpulseFact]
    var support: [AnalyticsSupportFact]
    var cycle: [AnalyticsCycleFact]
    var sleep: [SleepSessionSummary]
    var categories: [AnalyticsCategoryFact]
    var healthMedication: [Date: String]

    var earliest: Date? {
        let dates = checkIns.map(\.timestamp) + sessions.map(\.start) + hunger.map(\.eventDate)
            + food.map(\.eventDate) + emotions.map(\.eventDate) + impulses.map(\.eventDate)
            + support.map(\.day) + cycle.map(\.day) + sleep.map(\.start)
        return dates.min()
    }

    var isEmpty: Bool {
        checkIns.isEmpty && sessions.isEmpty && hunger.isEmpty && food.isEmpty
            && emotions.isEmpty && impulses.isEmpty && support.isEmpty && cycle.isEmpty && sleep.isEmpty
    }
}

enum AnalyticsFactsCapture {
    @MainActor
    static func capture(
        checkIns: [CheckIn],
        sessions: [FocusSession],
        conditionEvents: [ConditionEvent] = [],
        hunger: [HungerEntry],
        food: [FoodEntry],
        emotions: [EmotionEntry],
        impulses: [ImpulseEntry],
        support: [SupportEntry],
        cycle: [CycleEntry],
        categories: [FactorCategory],
        sleep: [SleepSessionSummary],
        healthCycle: [CycleMark],
        healthMedication: [Date: HealthMedicationDay],
        now: Date = .now
    ) -> AnalyticsFacts {
        let sessionFacts = sessions.map { session in
            AnalyticsSessionFact(
                id: session.id,
                activity: session.activity,
                typeRaw: session.sessionTypeRaw,
                start: session.startDate,
                end: session.endDate,
                stateRaw: session.stateRaw,
                activeDuration: session.activeWorkDuration(asOf: now),
                breakDuration: session.breakDuration(asOf: now),
                checkInIDs: (session.checkIns ?? []).map(\.id)
            )
        }
        let enabledByCategory = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.isEnabled) })
        let checkInFacts = checkIns.map { entry in
            AnalyticsCheckInFact(
                id: entry.id,
                timestamp: entry.timestamp,
                mood: entry.mood.scale,
                moodRaw: entry.mood.rawValue,
                energy: entry.energy?.scale,
                motivation: entry.motivation?.scale,
                reason: entry.reason,
                sessionID: entry.session?.id,
                conditions: entry.conditionSnapshot.map {
                    AnalyticsConditionFact(
                        categoryID: $0.categoryID,
                        optionID: $0.optionID,
                        categoryName: $0.categoryName,
                        optionName: $0.optionName,
                        icon: $0.categoryIcon,
                        iconImageName: $0.resolvedIconImageName,
                        categoryEnabled: enabledByCategory[$0.categoryID] ?? true
                    )
                }
            )
        }
        let categoryFacts = categories.map { category in
            AnalyticsCategoryFact(
                id: category.id,
                name: category.name,
                icon: category.icon,
                iconImageName: category.iconImageName,
                isEnabled: category.isEnabled,
                options: (category.options ?? []).map {
                    AnalyticsOptionFact(id: $0.id, name: $0.name, icon: $0.icon, iconImageName: $0.iconImageName ?? category.iconImageName)
                }
            )
        }
        let cycleFacts = cycle.map {
            AnalyticsCycleFact(day: $0.date, kindRaw: $0.kind.rawValue, sourceRaw: SleepSource.manual.rawValue)
        } + healthCycle.map {
            AnalyticsCycleFact(day: $0.day, kindRaw: $0.kind.rawValue, sourceRaw: $0.source.rawValue)
        }
        var medStatus: [Date: String] = [:]
        for (day, record) in healthMedication {
            if let status = record.status { medStatus[day] = status.rawValue }
        }
        let eventFacts = conditionEvents.map {
            AnalyticsConditionEventFact(
                id: $0.id,
                timestamp: $0.timestamp,
                categoryID: $0.categoryID,
                optionID: $0.optionID,
                sessionID: $0.session?.id
            )
        }
        return AnalyticsFacts(
            checkIns: checkInFacts,
            sessions: sessionFacts,
            conditionEvents: eventFacts,
            hunger: hunger.filter { !$0.isEmpty }.map {
                AnalyticsHungerFact(id: $0.id, eventDate: $0.eventDate, hunger: $0.hunger?.scale, appetite: $0.appetite?.scale)
            },
            food: food.map {
                AnalyticsFoodFact(id: $0.id, eventDate: $0.eventDate, categoryRaw: $0.category.rawValue, fullness: $0.fullness?.scale)
            },
            emotions: emotions.filter { !$0.isEmpty }.map {
                AnalyticsEmotionFact(id: $0.id, eventDate: $0.eventDate, emotions: $0.emotions.map(\.rawValue))
            },
            impulses: impulses.map {
                AnalyticsImpulseFact(id: $0.id, eventDate: $0.eventDate, categoryRaw: $0.category.rawValue, outcomeRaw: $0.outcome?.rawValue)
            },
            support: support.map {
                AnalyticsSupportFact(id: $0.id, day: $0.day, statusRaw: $0.status.rawValue)
            },
            cycle: cycleFacts,
            sleep: sleep,
            categories: categoryFacts,
            healthMedication: medStatus
        )
    }
}
