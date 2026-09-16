//
//  EnergyLevel.swift
//  Mood Pomodoro
//

import Foundation

/// How much energy there was at a check-in — the body's side of the day,
/// separate from how the work felt (`Mood`) and from wanting to do it
/// (`StudyMotivation`). Optional on every check-in: a mood can be logged
/// without answering this.
enum EnergyLevel: String, LevelScale {
    case veryHigh
    case high
    case medium
    case low
    case veryLow

    var id: String { rawValue }

    static var orderedCases: [EnergyLevel] { [.veryHigh, .high, .medium, .low, .veryLow] }

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
        case .veryHigh: return L("Полна сил", "Full of energy")
        case .high: return L("Много сил", "Plenty of energy")
        case .medium: return L("Средне", "So-so")
        case .low: return L("Мало сил", "Low on energy")
        case .veryLow: return L("Совсем без сил", "Running on empty")
        }
    }

    var imageName: String {
        switch self {
        case .veryHigh: return "EnergyVeryHigh"
        case .high: return "EnergyHigh"
        case .medium: return "EnergyMedium"
        case .low: return "EnergyLow"
        case .veryLow: return "EnergyVeryLow"
        }
    }

    /// Used where an illustration can't be drawn — notification text, the
    /// diary export, a one-line timeline row. Moon phases: they grade
    /// cleanly at small sizes and don't read as a mood or as an arrow, so
    /// the three scales stay tellable apart on one line.
    var emoji: String {
        switch self {
        case .veryHigh: return "🌕"
        case .high: return "🌔"
        case .medium: return "🌓"
        case .low: return "🌒"
        case .veryLow: return "🌑"
        }
    }
}
