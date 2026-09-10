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
