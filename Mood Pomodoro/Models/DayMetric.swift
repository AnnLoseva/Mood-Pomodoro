//
//  DayMetric.swift
//  Mood Pomodoro
//

import SwiftUI

/// The three things a check-in can record, as the day chart's series. Each
/// is a `LevelScale`, so they share one 1–5 axis and can be drawn together
/// or one at a time.
///
/// Only `mood` is shown on the month screen: a month is a coarse view, and
/// three overlaid lines there would say less than one.
enum DayMetric: String, CaseIterable, Identifiable, Codable {
    case mood
    case energy
    case motivation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: return L("Настроение", "Mood")
        case .energy: return L("Энергия", "Energy")
        case .motivation: return L("Мотивация", "Motivation")
        }
    }

    /// Green, yellow, red — traffic-light hues, kept muted enough to sit in
    /// the parchment palette but far enough apart to stay tellable apart
    /// over the tinted activity bands behind them.
    var color: Color {
        switch self {
        case .mood: return AppTheme.forest
        case .energy: return Color(red: 0.882, green: 0.694, blue: 0.129)
        case .motivation: return Color(red: 0.749, green: 0.239, blue: 0.204)
        }
    }

    /// The illustration for a step of this metric's scale, for the chart's
    /// Y axis and for a legend chip.
    func imageName(forScale value: Int) -> String? {
        switch self {
        case .mood: return Mood.atScale(value)?.imageName
        case .energy: return EnergyLevel.atScale(value)?.imageName
        case .motivation: return StudyMotivation.atScale(value)?.imageName
        }
    }

    func emoji(forScale value: Int) -> String? {
        switch self {
        case .mood: return Mood.atScale(value)?.emoji
        case .energy: return EnergyLevel.atScale(value)?.emoji
        case .motivation: return StudyMotivation.atScale(value)?.emoji
        }
    }

    /// The name of the step closest to an average, e.g. under the chart.
    func label(forAverage average: Double) -> String? {
        switch self {
        case .mood: return Mood.closest(to: average)?.label
        case .energy: return EnergyLevel.closest(to: average)?.label
        case .motivation: return StudyMotivation.closest(to: average)?.label
        }
    }
}
