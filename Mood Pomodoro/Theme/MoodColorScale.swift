//
//  MoodColorScale.swift
//  Mood Pomodoro
//

import SwiftUI

/// Average mood → color, for the month calendar. Muted woodland tones
/// (terracotta → ochre → moss → forest) so it sits in the goblincore
/// palette, but still reads unmistakably as red-is-hard, green-is-good.
///
/// "No data" is intentionally *not* on this scale — an empty day gets
/// `AppTheme` parchment and an outline, never a color that could be read as
/// a mood.
enum MoodColorScale {
    private struct Stop {
        let value: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let stops: [Stop] = [
        Stop(value: 1, red: 0.690, green: 0.294, blue: 0.247), // muted red
        Stop(value: 2, red: 0.800, green: 0.498, blue: 0.314), // terracotta
        Stop(value: 3, red: 0.851, green: 0.737, blue: 0.408), // warm ochre
        Stop(value: 4, red: 0.580, green: 0.667, blue: 0.392), // moss
        Stop(value: 5, red: 0.310, green: 0.490, blue: 0.294)  // forest
    ]

    /// Continuous: 2.67 lands between terracotta and ochre, as it should.
    static func color(for average: Double) -> Color {
        let (red, green, blue) = components(for: average)
        return Color(red: red, green: green, blue: blue)
    }

    /// Whether the day number drawn on top should be light — the two ends
    /// of the scale are dark enough that bark-brown ink loses contrast.
    static func prefersLightText(for average: Double) -> Bool {
        let (red, green, blue) = components(for: average)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance < 0.5
    }

    /// Legend swatches, best first — matches `Mood.orderedCases`.
    static var legend: [(mood: Mood, color: Color)] {
        Mood.orderedCases.map { ($0, color(for: $0.scale)) }
    }

    /// Raw RGB for `average` — internal so tests can check the scale's shape.
    static func components(for average: Double) -> (Double, Double, Double) {
        let value = min(max(average, 1), 5)
        guard let upperIndex = stops.firstIndex(where: { $0.value >= value }) else {
            let last = stops[stops.count - 1]
            return (last.red, last.green, last.blue)
        }
        guard upperIndex > 0 else {
            let first = stops[0]
            return (first.red, first.green, first.blue)
        }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let t = (value - lower.value) / (upper.value - lower.value)
        return (
            lower.red + (upper.red - lower.red) * t,
            lower.green + (upper.green - lower.green) * t,
            lower.blue + (upper.blue - lower.blue) * t
        )
    }
}
