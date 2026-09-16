//
//  Mood.swift
//  Mood Pomodoro
//

import Foundation

/// The five subjective states a check-in can record. One of the three
/// `LevelScale`s the day chart draws, alongside `EnergyLevel` and
/// `StudyMotivation` — and the only one the month screen shows.
enum Mood: String, CaseIterable, Codable, Identifiable {
    case veryGood
    case good
    case neutral
    case tired
    case veryBad

    var id: String { rawValue }

    /// Display order, from best to worst — matches the order used throughout the UI.
    static var orderedCases: [Mood] { [.veryGood, .good, .neutral, .tired, .veryBad] }

    /// Stable ID used in `UNNotificationAction.identifier` (`mood.very_good`).
    /// Not the display string — iOS matches actions by this ID.
    var notificationActionID: String {
        switch self {
        case .veryGood: return "very_good"
        case .good: return "good"
        case .neutral: return "normal"
        case .tired: return "hard"
        case .veryBad: return "very_bad"
        }
    }

    static func fromNotificationActionID(_ id: String) -> Mood? {
        orderedCases.first { $0.notificationActionID == id }
    }

    var emoji: String {
        switch self {
        case .veryGood: return "😍"
        case .good: return "😄"
        case .neutral: return "🙂"
        case .tired: return "🥲"
        case .veryBad: return "😭"
        }
    }

    /// Asset name of this mood's mushroom character illustration.
    var imageName: String {
        switch self {
        case .veryGood: return "MoodVeryGood"
        case .good: return "MoodGood"
        case .neutral: return "MoodNeutral"
        case .tired: return "MoodTired"
        case .veryBad: return "MoodVeryBad"
        }
    }

    /// Numeric position on the 1–5 scale, veryBad=1 … veryGood=5. Used only to
    /// average/compare moods in Analytics — never surfaced as a "score" to the
    /// user (the UI always shows the emoji/label, not the number, except as
    /// the small "3.8 / 5" summary figure the spec explicitly asks for).
    var scale: Double {
        switch self {
        case .veryGood: return 5
        case .good: return 4
        case .neutral: return 3
        case .tired: return 2
        case .veryBad: return 1
        }
    }

    /// True for the two lower states — used to find "time to first difficult moment".
    var isDifficult: Bool { self == .tired || self == .veryBad }

    /// SF Symbol used as the `UNNotificationAction` icon (iOS 15+).
    var notificationIconName: String {
        switch self {
        case .veryGood: return "heart.fill"
        case .good: return "face.smiling"
        case .neutral: return "face.smiling"
        case .tired: return "cloud.rain"
        case .veryBad: return "cloud.heavyrain.fill"
        }
    }

    var label: String {
        switch self {
        case .veryGood: return L("Очень хорошо", "Very good")
        case .good: return L("Хорошо", "Good")
        case .neutral: return L("Нормально", "Okay")
        case .tired: return L("Плохо", "Bad")
        case .veryBad: return L("Очень плохо", "Very bad")
        }
    }

    /// Seed values for `ReasonsStore`. Kept here only as defaults — the store owns
    /// the editable copy so a future "edit reasons" screen doesn't touch this enum.
    ///
    /// Strictly *emotional* — how she feels, not how the work is going.
    /// Anything about the work itself ("интересная тема", "я вошла в
    /// поток") belongs to `StudyMotivation.defaultReasons`; the earlier
    /// list here mixed the two, which is why the same answer could be
    /// given for a good mood and for wanting to continue.
    var defaultReasons: [String] {
        switch self {
        case .veryGood:
            return [
                "Просто очень хорошо",
                "Что-то порадовало",
                "Спокойно и приятно",
                "Чувствую воодушевление",
                "Всё сейчас нравится"
            ]
        case .good:
            return [
                "Просто хорошее настроение",
                "Приятно и спокойно",
                "Что-то подняло настроение",
                "Чувствую себя комфортно",
                "Сейчас всё ок"
            ]
        case .neutral:
            return [
                "Просто нейтрально",
                "Спокойно",
                "Ничего особенного",
                "Немного хорошо, немного тяжело",
                "Просто нормально"
            ]
        case .tired:
            return [
                "Что-то расстроило",
                "Тревожно",
                "Раздражена",
                "Грустно",
                "Сейчас эмоционально тяжело"
            ]
        case .veryBad:
            return [
                "Очень грустно",
                "Сильно тревожно",
                "Очень раздражена",
                "Что-то сильно задело",
                "Сейчас совсем тяжело"
            ]
        }
    }
}

/// Every requirement is already here; this just names the shared shape.
extension Mood: LevelScale {}
