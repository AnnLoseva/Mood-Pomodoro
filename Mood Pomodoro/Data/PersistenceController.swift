//
//  PersistenceController.swift
//  Mood Pomodoro
//
//  CloudKit private database is the remote source of truth. SwiftData is
//  the on-device cache so the timer, history and analytics keep working
//  offline. If CloudKit cannot be opened (no iCloud entitlement, signed
//  out, personal team), we fall back to a local store and never delete
//  existing history to do it.
//

import Foundation
import SwiftData

enum PersistenceController {
    static let schema = Schema([
        FocusSession.self,
        CheckIn.self,
        FactorCategory.self,
        FactorOption.self,
        ConditionEvent.self,
        SessionSegment.self,
        MoodReason.self,
        CycleEntry.self,
        SupportEntry.self,
        JournalNote.self,
        FoodEntry.self,
        HungerEntry.self,
        EmotionEntry.self,
        ImpulseEntry.self
    ])

    /// True when this process actually opened a CloudKit-backed store.
    private(set) static var isUsingCloudKit = false

    /// Requires the paid team (K36SNFAJDS) and `Mood Pomodoro.entitlements`
    /// attached to the app target (`CODE_SIGN_ENTITLEMENTS`). Flip back to
    /// `false` only for a Personal Team build, which can't sign iCloud.
    static let cloudKitEnabledInThisBuild = true

    static func makeContainer() -> ModelContainer {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MOOD_UI_TESTING"] == "1" {
            return seeded(try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        }
        #endif
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Do not construct a CloudKit container unless explicitly enabled —
        // otherwise CKContainer logs a process-level client bug.
        if !runningTests, cloudKitEnabledInThisBuild, let cloud = attempt(cloudKit: true) {
            isUsingCloudKit = true
            return seeded(cloud)
        }
        isUsingCloudKit = false
        if let local = attempt(cloudKit: false) {
            return seeded(local)
        }
        fatalError("Unable to open diary store. Existing data has been preserved; do not reset the database.")
    }

    /// The diary's own iCloud container. Named explicitly because the app also has a second
    /// container (`MoodPomodoroContract.cloudContainerID`) that holds ToDo List events only;
    /// with two containers in the entitlements `.automatic` would be ambiguous.
    static let diaryCloudContainerID = "iCloud.AnnaLoseva.Mood-Pomodoro"

    /// The store configuration, pinned on purpose.
    ///
    /// `groupContainer: .none` keeps the store where it has always been — the app's own
    /// container. Without it, SwiftData silently moves the default store into the App Group
    /// container as soon as the App Group capability exists (which the ToDo List
    /// integration needs): the app would open a new, empty diary while the real one stays
    /// behind. The App Group is used only for the integration mailbox.
    ///
    /// `cloudKitDatabase` defaults to `.automatic` — omitting it is NOT a local-only store.
    /// Tests and the iCloud-unavailable fallback must pass `.none` explicitly.
    static func configuration(cloudKit: Bool) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none,
            cloudKitDatabase: cloudKit ? .private(diaryCloudContainerID) : .none
        )
    }

    private static func attempt(cloudKit: Bool) -> ModelContainer? {
        let configuration = configuration(cloudKit: cloudKit)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            return nil
        }
    }

    private static func seeded(_ container: ModelContainer) -> ModelContainer {
        let context = ModelContext(container)
        FactorSeeder.seedIfNeeded(context: context)
        return container
    }

}
