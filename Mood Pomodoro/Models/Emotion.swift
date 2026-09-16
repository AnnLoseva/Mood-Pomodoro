//
//  Emotion.swift
//  Mood Pomodoro
//

import SwiftUI

/// A named feeling, recorded on its own. Deliberately **not** a scale and
/// deliberately not derived from `Mood`: "настроение 4" and "тревожная" are
/// two different answers to two different questions, and one can never be
/// computed from the other. Nothing here is averaged, scored or ranked —
/// an emotion is a label on a moment.
///
/// Exactly seven, in the order the picker shows them.
enum Emotion: String, CaseIterable, Codable, Identifiable, Sendable {
    case calm
    case angry
    case sad
    case happy
    case anxious
    case bored
    case interested

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calm: return L("Спокойно", "Calm")
        case .angry: return L("Злая", "Angry")
        case .sad: return L("Грустная", "Sad")
        case .happy: return L("Счастливая", "Happy")
        case .anxious: return L("Тревожная", "Anxious")
        case .bored: return L("Скучно", "Bored")
        case .interested: return L("Интересно", "Curious")
        }
    }

    /// The mushroom character drawn for this emotion. Real assets, sliced
    /// from the same sheet the moods and the food icons came from.
    var imageName: String {
        switch self {
        case .calm: return "EmotionCalm"
        case .angry: return "EmotionAngry"
        case .sad: return "EmotionSad"
        case .happy: return "EmotionHappy"
        case .anxious: return "EmotionAnxious"
        case .bored: return "EmotionBored"
        case .interested: return "EmotionInterested"
        }
    }

    /// Used where an illustration can't go: a one-line timeline row, the
    /// export, a chart marker's accessibility label.
    var emoji: String {
        switch self {
        case .calm: return "🍃"
        case .angry: return "🔥"
        case .sad: return "💧"
        case .happy: return "🌞"
        case .anxious: return "🌀"
        case .bored: return "🌫"
        case .interested: return "✨"
        }
    }

    /// Distinct woodland tones — far enough apart to tell seven markers on
    /// one chart lane apart, muted enough to stay inside the parchment
    /// palette. They are identifiers, not judgements: no colour here means
    /// "good" or "bad".
    var color: Color {
        switch self {
        case .calm: return AppTheme.moss
        case .angry: return Color(red: 0.706, green: 0.259, blue: 0.196)
        case .sad: return Color(red: 0.357, green: 0.463, blue: 0.604)
        case .happy: return Color(red: 0.882, green: 0.663, blue: 0.220)
        case .anxious: return Color(red: 0.494, green: 0.376, blue: 0.604)
        case .bored: return Color(red: 0.561, green: 0.549, blue: 0.451)
        case .interested: return Color(red: 0.243, green: 0.537, blue: 0.518)
        }
    }
}
