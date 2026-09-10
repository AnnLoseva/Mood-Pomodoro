//
//  Mood.swift
//  Mood Pomodoro
//

import Foundation

/// The five subjective states a check-in can record.
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
        case .veryGood: return "Очень хорошо"
        case .good: return "Хорошо"
        case .neutral: return "Нормально"
        case .tired: return "Тяжеловато"
        case .veryBad: return "Очень плохо"
        }
    }

    /// Seed values for `ReasonsStore`. Kept here only as defaults — the store owns
    /// the editable copy so a future "edit reasons" screen doesn't touch this enum.
    var defaultReasons: [String] {
        switch self {
        case .veryGood:
            return [
                "Интересная тема",
                "Я вошла в поток",
                "Всё легко получается",
                "Сложно, но мне нравится",
                "Просто хорошо себя чувствую"
            ]
        case .good:
            return [
                "Интересно",
                "Хорошо получается",
                "Нравится процесс",
                "Получается лучше, чем ожидала",
                "Просто хорошее состояние"
            ]
        case .neutral:
            return [
                "Нормально",
                "Не особо интересно, но терпимо",
                "Не сложно",
                "Не легко",
                "Просто нейтрально"
            ]
        case .tired:
            return [
                "Устала",
                "Уже начинает надоедать",
                "Сложно",
                "Понимаю, но не хочется продолжать",
                "Хочу закончить"
            ]
        case .veryBad:
            return [
                "Я достаточно устала и хочу спать",
                "Меня уже тошнит от этого",
                "Мне не интересно, но я продолжаю сидеть",
                "Зачем я вообще этим занимаюсь?",
                "Я вообще ничего не понимаю / слишком сложно"
            ]
        }
    }
}
