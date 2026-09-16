//
//  SleepPrivacyTests.swift
//  Mood PomodoroTests
//

import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

/// The CloudKit separation, as a test rather than a comment.
///
/// Apple's review guidelines forbid storing personal health information in
/// iCloud. The app's main container is opened with
/// `cloudKitDatabase: .automatic`, which syncs **every model in its
/// schema** — so the rule is enforced by keeping `SleepRecord` out of that
/// schema entirely, and the thing most likely to break it in future is
/// someone adding the model to the wrong list in a hurry.
///
/// These tests fail loudly if that ever happens.
struct SleepPrivacyTests {

    private var cloudSchemaNames: [String] {
        PersistenceController.schema.entities.map(\.name)
    }

    @Test func healthDerivedRecordsAreNotInTheCloudKitSyncedSchema() {
        // The whole rule, in three assertions.
        for entity in ["SleepRecord", "HealthCycleDay", "HealthMedicationDay"] {
            #expect(!cloudSchemaNames.contains(entity), "\(entity) must never sync to iCloud")
        }
    }

    @Test func theCloudKitSchemaStillHoldsEverythingItAlwaysDid() {
        // The separation must not have been achieved by quietly dropping
        // something that is supposed to sync.
        for entity in [
            "FocusSession", "CheckIn", "FactorCategory", "FactorOption",
            "ConditionEvent", "SessionSegment", "MoodReason", "CycleEntry",
            "SupportEntry", "JournalNote", "FoodEntry", "HungerEntry"
        ] {
            #expect(cloudSchemaNames.contains(entity), "\(entity) should still sync")
        }
    }

    @Test func theLocalHealthSchemaHoldsOnlyHealthDerivedRecords() {
        let names = Set(LocalHealthStore.schema.entities.map(\.name))
        // Everything read from Apple Health — sleep, cycle, medication —
        // and nothing that belongs to the synced diary.
        #expect(names == ["SleepRecord", "HealthCycleDay", "HealthMedicationDay"])
    }

    /// The two stores must be genuinely separate objects, not the same
    /// container reached two ways.
    @Test func theHealthContainerIsNotTheAppContainer() {
        let healthNames = Set(LocalHealthStore.schema.entities.map(\.name))
        let cloudNames = Set(cloudSchemaNames)
        #expect(healthNames.isDisjoint(with: cloudNames))
    }

    /// A sanity check on the model itself: it carries no relationship to
    /// anything in the synced graph, which is the other way a record could
    /// be dragged into CloudKit.
    @Test func healthRecordsHaveNoRelationshipsIntoTheSyncedGraph() {
        for entity in LocalHealthStore.schema.entities {
            #expect(entity.relationships.isEmpty, "\(entity.name) must not link into the synced graph")
        }
    }

    /// Manual entries are health information too, and live in the same
    /// local-only store — one class of sleep in iCloud and another out would
    /// be the worst of both worlds.
    @Test func manualSleepAlsoStaysOutOfTheSyncedStore() async {
        let store = await SleepStore(container: LocalHealthStore.container)
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2024, month: 9, day: 16, hour: 0, minute: 40))!
        let end = calendar.date(from: DateComponents(year: 2024, month: 9, day: 16, hour: 7, minute: 50))!

        let summary = await store.addManualSleep(start: start, end: end)
        #expect(summary?.source == .manual)
        // It landed in the local store…
        let sessions = await store.sessions
        #expect(sessions.contains { $0.id == summary?.id })
        // …and `SleepRecord` is still absent from the synced schema.
        #expect(!cloudSchemaNames.contains("SleepRecord"))

        if let id = summary?.id { await store.deleteSleep(id: id) }
    }
}
