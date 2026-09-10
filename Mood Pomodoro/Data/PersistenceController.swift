//
//  PersistenceController.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

enum PersistenceController {
    static let schema = Schema([FocusSession.self, CheckIn.self])

    /// CloudKit sync is intentionally off for the MVP (local storage only, per spec).
    /// The schema and configuration are isolated here so enabling `cloudKitDatabase`
    /// later is a one-line change instead of a rewrite.
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
