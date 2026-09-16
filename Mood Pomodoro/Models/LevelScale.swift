//
//  LevelScale.swift
//  Mood Pomodoro
//

import Foundation

/// What `Mood`, `EnergyLevel` and `StudyMotivation` have in common: five
/// steps on the same 1–5 scale, each with a name and an illustration. The
/// day chart and the check-in pickers are written against this, so all
/// three are recorded and drawn by one piece of code rather than three.
///
/// As with `Mood.scale`, the number is only ever used to place a point on a
/// chart or average a period — it is never shown to the user as a score.
/// Not `Sendable`: `Identifiable` here is main-actor isolated by the
/// project's default isolation, and these are only ever read from the UI.
protocol LevelScale: CaseIterable, Identifiable, Codable, Hashable {
    /// Display order, best first — the order every picker row uses.
    static var orderedCases: [Self] { get }
    var scale: Double { get }
    var label: String { get }
    var imageName: String { get }
    var emoji: String { get }
}

extension LevelScale {
    /// The step whose position is closest to an averaged value, for picking
    /// one illustration to stand for a period. Named apart from the
    /// concrete `Mood.nearest(to:)`, which predates this protocol and
    /// returns a non-optional.
    static func closest(to scale: Double) -> Self? {
        orderedCases.min { abs($0.scale - scale) < abs($1.scale - scale) }
    }

    /// The step sitting exactly on `value` (1–5), for axis labels.
    static func atScale(_ value: Int) -> Self? {
        orderedCases.first { Int($0.scale) == value }
    }
}
