import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

// Stored properties copied from commit 76043bd; no current model aliases.
enum LegacyDiary76043 {
    @Model
    final class FocusSession {
        var id: UUID = UUID()
        var activity: String = ""
        var startDate: Date = Date.now
        var endDate: Date?
        var checkInIntervalMinutes: Int = 10
        var stateRaw: String = SessionState.active.rawValue
        var originRaw: String = SessionOrigin.timer.rawValue
        var note: String?
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        @Relationship(deleteRule: .cascade, inverse: \CheckIn.session)
        var checkIns: [CheckIn]? = []
        @Relationship(deleteRule: .cascade, inverse: \ConditionEvent.session)
        var conditionEvents: [ConditionEvent]? = []
        @Relationship(deleteRule: .cascade, inverse: \SessionSegment.session)
        var segments: [SessionSegment]? = []
        init() {}
    }
    @Model
    final class CheckIn {
        var id: UUID = UUID()
        var timestamp: Date = Date.now
        var moodRaw: String = Mood.neutral.rawValue
        var energyRaw: String?
        var motivationRaw: String?
        var reason: String?
        var motivationReason: String?
        var note: String?
        var session: FocusSession?
        var conditionSnapshotJSON: Data = Data()
        var sourceIdentifier: String?
        var occurrenceID: String?
        var scheduledAt: Date?
        var originRaw: String = CheckInOrigin.manual.rawValue
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        init() {}
    }
    @Model
    final class FactorCategory {
        var id: UUID = UUID()
        var name: String = ""
        var icon: String = ""
        var iconImageName: String?
        var isEnabled: Bool = true
        var sortOrder: Int = 0
        @Relationship(deleteRule: .cascade, inverse: \FactorOption.category)
        var options: [FactorOption]? = []
        init() {}
    }
    @Model
    final class FactorOption {
        var id: UUID = UUID()
        var name: String = ""
        var icon: String = ""
        var iconImageName: String?
        var isEnabled: Bool = true
        var sortOrder: Int = 0
        var category: FactorCategory?
        init() {}
    }
    @Model
    final class ConditionEvent {
        var id: UUID = UUID()
        var timestamp: Date = Date.now
        var categoryID: UUID = UUID()
        var categoryName: String = ""
        var categoryIcon: String = ""
        var categoryIconImageName: String?
        var optionID: UUID = UUID()
        var optionName: String = ""
        var optionIconImageName: String?
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var session: FocusSession?
        init() {}
    }
    @Model
    final class SessionSegment {
        var id: UUID = UUID()
        var typeRaw: String = SegmentType.work.rawValue
        var startDate: Date = Date.now
        var endDate: Date?
        var createdAt: Date = Date.now
        var session: FocusSession?
        init() {}
    }
    @Model
    final class MoodReason {
        var id: UUID = UUID()
        var metricRaw: String = DayMetric.mood.rawValue
        var moodRaw: String = Mood.neutral.rawValue
        var text: String = ""
        var sortOrder: Int = 0
        var createdAt: Date = Date.now
        init() {}
    }
    @Model
    final class CycleEntry {
        var id: UUID = UUID()
        var date: Date = Date.now
        var kindRaw: String = CycleEventKind.periodStart.rawValue
        var note: String?
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        init() {}
    }
    @Model
    final class SupportEntry {
        var id: UUID = UUID()
        var trackerKey: String = "daily-support"
        var day: Date = Date.now
        var time: Date?
        var statusRaw: String = SupportStatus.taken.rawValue
        var note: String?
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        init() {}
    }
    @Model
    final class JournalNote {
        var id: UUID = UUID()
        var timestamp: Date = Date.now
        var text: String = ""
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        init() {}
    }
    @Model
    final class FoodEntry {
        var id: UUID = UUID()
        var eventDate: Date = Date.now
        var categoryRaw: String = FoodCategory.regular.rawValue
        var mealDensityRaw: String?
        var tasteRaw: String?
        var treatTypeRaw: String?
        var treatAmountRaw: String?
        var fullnessRaw: String?
        var desc: String?
        var note: String?
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        init() {}
    }
    @Model
    final class HungerEntry {
        var id: UUID = UUID()
        var eventDate: Date = Date.now
        var hungerRaw: String?
        var appetiteRaw: String?
        var note: String?
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        init() {}
    }
    static var schema: Schema { Schema([FocusSession.self, CheckIn.self, FactorCategory.self, FactorOption.self, ConditionEvent.self, SessionSegment.self, MoodReason.self, CycleEntry.self, SupportEntry.self, JournalNote.self, FoodEntry.self, HungerEntry.self]) }
}

@Suite(.serialized)
struct LegacyMigrationTests {
    @Test @MainActor func upgrade76043PreservesHistoryAndRelationships() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        let id = UUID()
        do {
            let schema = LegacyDiary76043.schema
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let session = LegacyDiary76043.FocusSession()
            session.id = id
            session.activity = "Old programming"
            session.note = "Keep this note"
            let checkIn = LegacyDiary76043.CheckIn()
            checkIn.moodRaw = Mood.veryGood.rawValue
            checkIn.session = session
            session.checkIns = [checkIn]
            let food = LegacyDiary76043.FoodEntry()
            old.mainContext.insert(session)
            old.mainContext.insert(food)
            try old.mainContext.save()
        }
        let schema = PersistenceController.schema
        let migrated = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let sessions = try migrated.mainContext.fetch(FetchDescriptor<FocusSession>())
        let session = try #require(sessions.first)
        #expect(sessions.count == 1 && session.id == id)
        #expect(session.activity == "Old programming" && session.note == "Keep this note")
        #expect(session.sessionType == nil)
        #expect(session.checkIns?.first?.mood == .veryGood)
        #expect(session.checkIns?.first?.session?.id == id)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<FoodEntry>()) == 1)
        let emotion = EmotionEntry(eventDate: .now, emotions: [.interested])
        migrated.mainContext.insert(emotion)
        try migrated.mainContext.save()
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<EmotionEntry>()) == 1)
    }
}
