//
//  StudyMotivation.swift
//  Mood Pomodoro
//

import Foundation

/// How much she wants to keep going with *this particular activity* — the
/// third of the three scales, and the one that is about the work rather
/// than about her: `Mood` is what she feels emotionally, `EnergyLevel` is
/// how much is left in the tank, and this is whether she wants to carry on.
/// Optional on every check-in.
enum StudyMotivation: String, LevelScale {
    case veryHigh
    case high
    case medium
    case low
    case veryLow

    var id: String { rawValue }

    static var orderedCases: [StudyMotivation] { [.veryHigh, .high, .medium, .low, .veryLow] }

    var scale: Double {
        switch self {
        case .veryHigh: return 5
        case .high: return 4
        case .medium: return 3
        case .low: return 2
        case .veryLow: return 1
        }
    }

    var label: String {
        switch self {
        case .veryHigh: return L("Очень хочу продолжать", "Really want to keep going")
        case .high: return L("Хочу продолжать", "Want to keep going")
        case .medium: return L("Нормально, могу продолжать", "Okay, I can keep going")
        case .low: return L("Уже не хочется", "Not feeling it anymore")
        case .veryLow: return L("Хочу прекратить прямо сейчас", "Want to stop right now")
        }
    }

    /// Seeds `ReasonsStore` the same way `Mood.defaultReasons` does — all
    /// about the activity: how it's going, whether it still holds her.
    var defaultReasons: [String] {
        switch self {
        case .veryHigh:
            return [
                "Материал очень интересный",
                "Поймала поток",
                "Очень хочется разобраться глубже",
                "Вижу заметный прогресс",
                "Очень нравится сам процесс"
            ]
        case .high:
            return [
                "Тема интересная",
                "Всё хорошо получается",
                "Есть понятная цель",
                "Хочется закончить начатое",
                "Сейчас приятно этим заниматься"
            ]
        case .medium:
            return [
                "Просто нормально идёт",
                "Материал понятный, но не цепляет",
                "Делаю потому что надо",
                "Немного устала, но терпимо",
                "Пока не надоело"
            ]
        case .low:
            return [
                "Материал слишком тяжёлый",
                "Материал скучный",
                "Устала от этого занятия",
                "Уже надоело делать одно и то же",
                "Начинает раздражать"
            ]
        case .veryLow:
            return [
                "Ничего не понимаю и это бесит",
                "Материал невыносимо скучный",
                "Я полностью вымоталась от этого",
                "Меня уже тошнит от этого действия",
                "Всё в этом сейчас раздражает"
            ]
        }
    }

    var imageName: String {
        switch self {
        case .veryHigh: return "MotivationVeryHigh"
        case .high: return "MotivationHigh"
        case .medium: return "MotivationMedium"
        case .low: return "MotivationLow"
        case .veryLow: return "MotivationVeryLow"
        }
    }

    /// Direction rather than a face: a face here would be read as a mood,
    /// and 🙂 is already `Mood.neutral`.
    var emoji: String {
        switch self {
        case .veryHigh: return "🔥"
        case .high: return "⬆️"
        case .medium: return "➡️"
        case .low: return "⬇️"
        case .veryLow: return "🛑"
        }
    }
}
