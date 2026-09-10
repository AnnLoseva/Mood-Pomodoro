//
//  ReasonsStore.swift
//  Mood Pomodoro
//

import Foundation
import Observation
import SwiftData

/// Holds the editable check-in reasons shown for each mood. Seeded from
/// `Mood.defaultReasons`. When a `ModelContext` is bound, reasons live in
/// SwiftData (`MoodReason`) so CloudKit can sync them; otherwise they stay
/// in UserDefaults so tests and first-launch-before-bind still work.
@MainActor
@Observable
final class ReasonsStore {
    static let shared = ReasonsStore()

    private(set) var reasons: [Mood: [String]]
    private var context: ModelContext?

    private let defaultsKey = "com.moodpomodoro.reasons.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            var map: [Mood: [String]] = [:]
            for mood in Mood.allCases {
                map[mood] = decoded[mood.rawValue] ?? mood.defaultReasons
            }
            self.reasons = map
        } else {
            var map: [Mood: [String]] = [:]
            for mood in Mood.allCases { map[mood] = mood.defaultReasons }
            self.reasons = map
        }
    }

    func bind(context: ModelContext) {
        self.context = context
        seedSwiftDataIfNeeded()
        reloadFromSwiftData()
        migrateUserDefaultsIfSwiftDataWasEmpty()
    }

    func reasons(for mood: Mood) -> [String] {
        reasons[mood] ?? mood.defaultReasons
    }

    func setReasons(_ newReasons: [String], for mood: Mood) {
        reasons[mood] = newReasons
        persist()
    }

    func reloadFromSwiftData() {
        guard let context else { return }
        let descriptor = FetchDescriptor<MoodReason>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        var map: [Mood: [String]] = [:]
        for mood in Mood.allCases { map[mood] = [] }
        for row in rows {
            map[row.mood, default: []].append(row.text)
        }
        for mood in Mood.allCases where (map[mood] ?? []).isEmpty {
            map[mood] = mood.defaultReasons
        }
        reasons = map
    }

    private func seedSwiftDataIfNeeded() {
        guard let context else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<MoodReason>())) ?? 0
        guard existing == 0 else { return }
        for mood in Mood.orderedCases {
            for (index, text) in mood.defaultReasons.enumerated() {
                context.insert(MoodReason(mood: mood, text: text, sortOrder: index))
            }
        }
        try? context.save()
    }

    private func migrateUserDefaultsIfSwiftDataWasEmpty() {
        // If SwiftData already had rows, bind() reloaded them. If we just
        // seeded defaults, overlay any UserDefaults edits from the local MVP.
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        var changed = false
        for mood in Mood.allCases {
            if let stored = decoded[mood.rawValue], stored != mood.defaultReasons {
                reasons[mood] = stored
                changed = true
            }
        }
        if changed { persist() }
    }

    private func persist() {
        let encodable = Dictionary(uniqueKeysWithValues: reasons.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        guard let context else { return }
        let existing = (try? context.fetch(FetchDescriptor<MoodReason>())) ?? []
        for row in existing { context.delete(row) }
        for mood in Mood.orderedCases {
            for (index, text) in (reasons[mood] ?? mood.defaultReasons).enumerated() {
                context.insert(MoodReason(mood: mood, text: text, sortOrder: index))
            }
        }
        try? context.save()
    }
}
