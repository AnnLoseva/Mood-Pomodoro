//
//  ReasonsStore.swift
//  Mood Pomodoro
//

import Foundation
import Observation
import SwiftData

/// Holds the editable check-in reasons shown for each level of each scale
/// that has them — `Mood` and `StudyMotivation` (energy is a level only).
/// Seeded from the enums' `defaultReasons`. When a `ModelContext` is bound,
/// reasons live in SwiftData (`MoodReason`) so CloudKit can sync them;
/// otherwise they stay in UserDefaults so tests and first-launch-before-bind
/// still work.
@MainActor
@Observable
final class ReasonsStore {
    static let shared = ReasonsStore()

    /// One level of one scale — "mood|veryGood", "motivation|low".
    struct LevelKey: Hashable {
        let metric: DayMetric
        let levelRaw: String

        var storageKey: String { "\(metric.rawValue)|\(levelRaw)" }

        init(metric: DayMetric, levelRaw: String) {
            self.metric = metric
            self.levelRaw = levelRaw
        }

        init(_ mood: Mood) { self.init(metric: .mood, levelRaw: mood.rawValue) }
        init(_ motivation: StudyMotivation) { self.init(metric: .motivation, levelRaw: motivation.rawValue) }
    }

    private(set) var reasons: [LevelKey: [String]]
    private var context: ModelContext?

    private let defaultsKey = "com.moodpomodoro.reasons.v2"
    /// v1 keyed its dictionary by bare `Mood` raw values and carried the
    /// old study-flavoured mood reasons. Read once, then left alone.
    private let legacyDefaultsKey = "com.moodpomodoro.reasons.v1"
    /// Bumped when the built-in lists change shape. Seeing a lower number
    /// means the rows in the store are the previous defaults and should be
    /// replaced — see `reseedIfDefaultsChanged`.
    private let seedVersionKey = "com.moodpomodoro.reasons.seedVersion"
    private let currentSeedVersion = 2

    /// Every level that has reasons, in the order they are seeded.
    static var allLevelKeys: [LevelKey] {
        Mood.orderedCases.map(LevelKey.init) + StudyMotivation.orderedCases.map(LevelKey.init)
    }

    private static var defaults: [LevelKey: [String]] {
        var map: [LevelKey: [String]] = [:]
        for mood in Mood.allCases { map[LevelKey(mood)] = mood.defaultReasons }
        for motivation in StudyMotivation.allCases { map[LevelKey(motivation)] = motivation.defaultReasons }
        return map
    }

    private init() {
        var map = Self.defaults
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            for key in map.keys {
                if let stored = decoded[key.storageKey] { map[key] = stored }
            }
        }
        self.reasons = map
    }

    func bind(context: ModelContext) {
        self.context = context
        reseedIfDefaultsChanged(in: context)
        seedSwiftDataIfNeeded()
        reloadFromSwiftData()
    }

    /// Mood-keyed view of the store, for the notification categories: the
    /// lock-screen flow asks mood then reason and never the other two
    /// scales, which need the app open to answer.
    var moodReasons: [Mood: [String]] {
        Dictionary(uniqueKeysWithValues: Mood.allCases.map { ($0, reasons(for: $0)) })
    }

    func reasons(for mood: Mood) -> [String] {
        reasons[LevelKey(mood)] ?? mood.defaultReasons
    }

    func reasons(for motivation: StudyMotivation) -> [String] {
        reasons[LevelKey(motivation)] ?? motivation.defaultReasons
    }

    func setReasons(_ newReasons: [String], for mood: Mood) {
        setReasons(newReasons, for: LevelKey(mood))
    }

    func setReasons(_ newReasons: [String], for motivation: StudyMotivation) {
        setReasons(newReasons, for: LevelKey(motivation))
    }

    func setReasons(_ newReasons: [String], for key: LevelKey) {
        reasons[key] = newReasons
        persist()
    }

    func reloadFromSwiftData() {
        guard let context else { return }
        dedupeRows(in: context)
        let descriptor = FetchDescriptor<MoodReason>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        var map: [LevelKey: [String]] = [:]
        for row in rows {
            map[LevelKey(metric: row.metric, levelRaw: row.levelRaw), default: []].append(row.text)
        }
        // A level with no rows of its own falls back to its defaults rather
        // than showing an empty list.
        for (key, fallback) in Self.defaults where (map[key] ?? []).isEmpty {
            map[key] = fallback
        }
        reasons = map
    }

    /// Both devices seed the default reasons before their first sync, so an
    /// import can double every row. Keep one row per (metric, level, text);
    /// the survivor is chosen by `id` so every device keeps the same one and
    /// the deletions never cancel each other out.
    private func dedupeRows(in context: ModelContext) {
        let rows = ((try? context.fetch(FetchDescriptor<MoodReason>())) ?? []).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        var seen: Set<String> = []
        var removed = false
        for row in rows {
            if !seen.insert("\(row.metricRaw)|\(row.levelRaw)|\(row.text)").inserted {
                context.delete(row)
                removed = true
            }
        }
        if removed { try? context.save() }
    }

    /// The built-in lists were rewritten once: the mood reasons used to mix
    /// in how the *work* was going, which now belongs to motivation. Rows
    /// that are still the old defaults are replaced; anything else in the
    /// store is left exactly as it is.
    private func reseedIfDefaultsChanged(in context: ModelContext) {
        let seeded = UserDefaults.standard.integer(forKey: seedVersionKey)
        guard seeded < currentSeedVersion else { return }
        defer { UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey) }

        let rows = (try? context.fetch(FetchDescriptor<MoodReason>())) ?? []
        guard !rows.isEmpty else { return }
        let stale = Set(Self.version1MoodReasons)
        let obsolete = rows.filter { $0.metric == .mood && stale.contains($0.text) }
        guard !obsolete.isEmpty else { return }
        for row in obsolete { context.delete(row) }
        try? context.save()
        // Whatever is left keeps its place; `seedSwiftDataIfNeeded` fills
        // back in the levels this emptied.
    }

    private func seedSwiftDataIfNeeded() {
        guard let context else { return }
        let rows = (try? context.fetch(FetchDescriptor<MoodReason>())) ?? []
        var present: Set<String> = []
        for row in rows { present.insert(LevelKey(metric: row.metric, levelRaw: row.levelRaw).storageKey) }
        var inserted = false
        for key in Self.allLevelKeys where !present.contains(key.storageKey) {
            for (index, text) in (Self.defaults[key] ?? []).enumerated() {
                context.insert(MoodReason(metric: key.metric, levelRaw: key.levelRaw, text: text, sortOrder: index))
                inserted = true
            }
        }
        if inserted { try? context.save() }
    }

    private func persist() {
        let encodable = Dictionary(uniqueKeysWithValues: reasons.map { ($0.key.storageKey, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        guard let context else { return }
        let existing = (try? context.fetch(FetchDescriptor<MoodReason>())) ?? []
        for row in existing { context.delete(row) }
        for key in Self.allLevelKeys {
            for (index, text) in (reasons[key] ?? Self.defaults[key] ?? []).enumerated() {
                context.insert(MoodReason(metric: key.metric, levelRaw: key.levelRaw, text: text, sortOrder: index))
            }
        }
        try? context.save()
    }

    /// The mood reasons shipped before the three scales were separated.
    /// Only used to recognize a store still holding them.
    private static let version1MoodReasons: [String] = [
        "Интересная тема", "Я вошла в поток", "Всё легко получается",
        "Сложно, но мне нравится", "Просто хорошо себя чувствую",
        "Интересно", "Хорошо получается", "Нравится процесс",
        "Получается лучше, чем ожидала", "Просто хорошее состояние",
        "Нормально", "Не особо интересно, но терпимо", "Не сложно",
        "Не легко", "Просто нейтрально",
        "Устала", "Уже начинает надоедать", "Сложно",
        "Понимаю, но не хочется продолжать", "Хочу закончить",
        "Я достаточно устала и хочу спать", "Меня уже тошнит от этого",
        "Мне не интересно, но я продолжаю сидеть",
        "Зачем я вообще этим занимаюсь?",
        "Я вообще ничего не понимаю / слишком сложно"
    ]
}
