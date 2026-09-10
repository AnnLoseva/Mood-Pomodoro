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
        MoodReason.self
    ])

    /// True when this process actually opened a CloudKit-backed store.
    private(set) static var isUsingCloudKit = false

    static func makeContainer() -> ModelContainer {
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Do not construct a CloudKit container unless the binary is actually
        // entitled — otherwise CKContainer logs a process-level client bug.
        if !runningTests, ProcessEntitlements.supportsCloudKit, let cloud = attempt(cloudKit: true) {
            isUsingCloudKit = true
            return seeded(cloud)
        }
        isUsingCloudKit = false
        if let local = attempt(cloudKit: false) {
            return seeded(local)
        }
        destroyPersistentStore()
        if let local = attempt(cloudKit: false) {
            return seeded(local)
        }
        fatalError("Failed to create ModelContainer after resetting the store")
    }

    private static func attempt(cloudKit: Bool) -> ModelContainer? {
        // `cloudKitDatabase` defaults to `.automatic` — omitting it is NOT a
        // local-only store. Tests and the iCloud-unavailable fallback must
        // pass `.none` explicitly.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKit ? .automatic : .none
        )
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

    private static func destroyPersistentStore() {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let contents = (try? fileManager.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix("default.store") {
            try? fileManager.removeItem(at: url)
        }
    }
}
