//
//  ReasonsStore.swift
//  Mood Pomodoro
//

import Foundation
import Observation

/// Holds the editable check-in reasons shown for each mood. Seeded from
/// `Mood.defaultReasons` and persisted to UserDefaults, so a future "edit
/// reasons" screen only needs to read/write this store — nothing else in
/// the app hardcodes the reason lists.
@MainActor
@Observable
final class ReasonsStore {
    static let shared = ReasonsStore()

    private(set) var reasons: [Mood: [String]]

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

    func reasons(for mood: Mood) -> [String] {
        reasons[mood] ?? mood.defaultReasons
    }

    func setReasons(_ newReasons: [String], for mood: Mood) {
        reasons[mood] = newReasons
        persist()
    }

    private func persist() {
        let encodable = Dictionary(uniqueKeysWithValues: reasons.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
