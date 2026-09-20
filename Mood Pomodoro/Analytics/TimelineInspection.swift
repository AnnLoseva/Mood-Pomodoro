//
//  TimelineInspection.swift
//  Mood Pomodoro
//
//  The parts of the unified diary chart that decide *what a tap means*,
//  kept apart from drawing so they can be tested: which layers are on, what
//  value to report at a moment (and how sure the app is of it), and which
//  marks lie under a fingertip.
//

import Foundation
import CoreGraphics

// MARK: - Layer selection

/// Which layers the diary chart shows. Stored as one string so a choice
/// survives relaunches. An empty string is a real choice — "nothing on" —
/// not a request for the defaults: a layer the user switched off must not
/// come back by itself when the date changes.
struct TimelineLayerSelection: Equatable, Sendable {
    private(set) var layers: Set<TimelineLayer>

    static let defaultRaw = "mood,sleep,food"
    static let `default` = TimelineLayerSelection(raw: defaultRaw)

    init(raw: String) {
        layers = Set(raw.split(separator: ",").compactMap { TimelineLayer(rawValue: String($0)) })
    }

    init(layers: Set<TimelineLayer>) { self.layers = layers }

    var raw: String { layers.map(\.rawValue).sorted().joined(separator: ",") }

    func contains(_ layer: TimelineLayer) -> Bool { layers.contains(layer) }

    mutating func toggle(_ layer: TimelineLayer) {
        if layers.contains(layer) { layers.remove(layer) } else { layers.insert(layer) }
    }

    /// The lines that are on, in their fixed order.
    var lines: [TimelineLayer] { TimelineLayer.lineLayers.filter(layers.contains) }
    /// The marks and intervals that are on, in their fixed order.
    var marks: [TimelineLayer] { TimelineLayer.markLayers.filter(layers.contains) }
    var isEmpty: Bool { layers.isEmpty }
}

/// How sleep is drawn in a week or a month.
enum TimelineSleepStyle: String, CaseIterable, Identifiable, Sendable {
    case line, bands
    var id: String { rawValue }
    var title: String {
        switch self {
        case .line: return L("Линия", "Line")
        case .bands: return L("Полосы", "Bands")
        }
    }
}

// MARK: - Reading a value

/// A number the card reports at a moment, and where it came from. The chart
/// never presents an estimate as a measurement.
struct TimelineValueReading: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// A record made at (almost) this moment.
        case recorded
        /// Read off the line between two records.
        case interpolated(from: Date, to: Date)
        /// No record here; the closest one, that far away.
        case nearest(at: Date)
        /// The mean of the day's line, for week and month views.
        case dailyAverage
    }

    let value: Double
    let source: Source
}

enum TimelineInspection {
    /// Tolerance for "a record made at this moment".
    static let exactTolerance: TimeInterval = 90

    /// What `groups` (one line's records, sorted, already split where the
    /// line breaks) says at `time`.
    ///
    /// - `daily`: the groups hold one mark per day (week and month). Only
    ///   that day's own mean is reported — no line is read between days.
    /// - otherwise: a record at this moment; else the line between two
    ///   records of one group, flagged as interpolated; else the closest
    ///   record within `nearWindow`, flagged as nearest; else nothing.
    static func reading(
        groups: [[TimelineMark]],
        daily: Bool,
        at time: Date,
        nearWindow: TimeInterval,
        calendar: Calendar = .current
    ) -> TimelineValueReading? {
        if daily {
            for mark in groups.flatMap({ $0 }) where calendar.isDate(mark.date, inSameDayAs: time) {
                if let value = mark.value { return TimelineValueReading(value: value, source: .dailyAverage) }
            }
            return nil
        }

        let all = groups.flatMap { $0 }.filter { $0.value != nil }
        if let exact = all.min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
           abs(exact.date.timeIntervalSince(time)) <= exactTolerance, let value = exact.value {
            return TimelineValueReading(value: value, source: .recorded)
        }

        for group in groups {
            for (a, b) in zip(group, group.dropFirst()) {
                let gap = b.date.timeIntervalSince(a.date)
                guard gap > 0, time > a.date, time < b.date, let va = a.value, let vb = b.value else { continue }
                let k = time.timeIntervalSince(a.date) / gap
                return TimelineValueReading(value: va + (vb - va) * k, source: .interpolated(from: a.date, to: b.date))
            }
        }

        if let nearest = all.min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
           abs(nearest.date.timeIntervalSince(time)) <= nearWindow, let value = nearest.value {
            return TimelineValueReading(value: value, source: .nearest(at: nearest.date))
        }
        return nil
    }

    // MARK: - Hit testing

    /// Every mark within `radius` of `tap`, nearest first, each once. Several
    /// marks in one place (two emotions at one instant, an activity under a
    /// meal) are all returned so the card can offer each of them.
    static func candidates(
        _ positioned: [(mark: TimelineMark, point: CGPoint)],
        at tap: CGPoint,
        radius: CGFloat,
        limit: Int = 8
    ) -> [TimelineMark] {
        var seen = Set<String>()
        return positioned
            .map { (mark: $0.mark, distance: hypot($0.point.x - tap.x, $0.point.y - tap.y)) }
            .filter { $0.distance <= radius }
            .sorted { $0.distance < $1.distance }
            .compactMap { seen.insert($0.mark.id).inserted ? $0.mark : nil }
            .prefix(limit)
            .map { $0 }
    }

    /// Bands (sleep, activities) that cover `time` — a tap inside a band has
    /// no single point to land on.
    static func bands(_ bands: [TimelineMark], covering time: Date) -> [TimelineMark] {
        bands.filter { time >= $0.date && time <= ($0.end ?? $0.date) }
    }
}
