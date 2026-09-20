//
//  AnalyticsMetric.swift
//  Mood Pomodoro
//
//  What the analytics charts can plot, with the scale and unit each one is
//  read on. Values come straight from `AnalyticsDayRow` — the engine's own
//  daily rows — so nothing is recomputed here. A day that recorded nothing
//  for a metric yields `nil`, never zero.
//

import SwiftUI

enum AnalyticsMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case mood, energy, motivation, satiety, appetite
    case sleep, activity, rest, work, study

    var id: String { rawValue }

    enum Unit: Sendable, Equatable {
        /// A 1–5 self-rating. The same axis for every rating.
        case rating
        /// Hours. Only compared on one axis with other hours.
        case hours
    }

    var unit: Unit {
        switch self {
        case .mood, .energy, .motivation, .satiety, .appetite: return .rating
        case .sleep, .activity, .rest, .work, .study: return .hours
        }
    }

    var title: String {
        switch self {
        case .mood: return L("Настроение", "Mood")
        case .energy: return L("Энергия", "Energy")
        case .motivation: return L("Мотивация", "Motivation")
        case .satiety: return L("Сытость", "Satiety")
        case .appetite: return L("Аппетит", "Appetite")
        case .sleep: return L("Сон", "Sleep")
        case .activity: return L("Занятия", "Activities")
        case .rest: return L("Отдых", "Rest")
        case .work: return L("Обязательная работа", "Obligatory work")
        case .study: return L("Учёба", "Study")
        }
    }

    /// One short phrase for the unit and direction of the scale.
    var unitNote: String {
        switch unit {
        case .rating:
            return self == .satiety
                ? L("шкала 1–5, выше — сытнее", "scale 1–5, higher is fuller")
                : L("шкала 1–5", "scale 1–5")
        case .hours:
            return L("часы", "hours")
        }
    }

    /// How a day's value was formed — the "how is this calculated" line.
    var methodNote: String {
        switch self {
        case .mood, .energy, .motivation, .appetite:
            return L("Среднее за день по времени между отметками, а не по их числу.", "Daily mean over time between check-ins, not over their count.")
        case .satiety:
            return L("Голод записан как 1–5; на графике он перевёрнут (6 − голод), чтобы линия росла с сытостью.", "Hunger is recorded 1–5; the chart flips it (6 − hunger) so the line rises with fullness.")
        case .sleep:
            return L("Ночной сон за день пробуждения, часы. Дневной сон считается отдельно.", "Night sleep on the day you woke up, in hours. Naps are counted separately.")
        case .activity:
            return L("Активное время всех сессий за день, без пауз.", "Active time of all sessions that day, breaks excluded.")
        case .rest, .work, .study:
            return L("Активное время сессий этого типа за день, без пауз.", "Active time of this type of session that day, breaks excluded.")
        }
    }

    var palette: AnalyticsPalette.RGB {
        switch self {
        case .mood: return AnalyticsPalette.mood
        case .energy: return AnalyticsPalette.energy
        case .motivation: return AnalyticsPalette.motivation
        case .satiety: return AnalyticsPalette.hunger
        case .appetite: return AnalyticsPalette.appetite
        case .sleep: return AnalyticsPalette.sleep
        case .activity, .rest, .work, .study: return AnalyticsPalette.activity
        }
    }

    var color: Color { palette.color }
    var textColor: Color { AnalyticsPalette.text(palette).color }

    var shape: SeriesShape {
        switch self {
        case .mood: return .circle
        case .energy: return .square
        case .motivation: return .triangle
        case .satiety: return .diamond
        case .appetite: return .plus
        case .sleep: return .circle
        case .activity: return .square
        case .rest: return .triangle
        case .work: return .diamond
        case .study: return .plus
        }
    }

    /// Metrics offered first in every picker.
    static let primary: [AnalyticsMetric] = [.mood, .energy, .motivation, .sleep, .activity]
    static let secondary: [AnalyticsMetric] = [.satiety, .appetite, .rest, .work, .study]

    // MARK: - Reading a day

    /// This metric's value on `row`, in its own unit (rating or hours).
    func value(in row: AnalyticsDayRow) -> Double? {
        switch self {
        case .mood: return row.mood
        case .energy: return row.energy
        case .motivation: return row.motivation
        case .satiety: return row.hunger.map { 6 - $0 }
        case .appetite: return row.appetite
        case .sleep: return row.sleepSeconds.map { $0 / 3600 }
        case .activity:
            let seconds = row.durationByType.values.reduce(0, +)
            return seconds > 0 ? seconds / 3600 : nil
        case .rest: return hours(row, SessionType.rest.rawValue)
        case .work: return hours(row, SessionType.obligatoryWork.rawValue)
        case .study: return hours(row, SessionType.study.rawValue)
        }
    }

    /// How many records the day's value rests on, when the engine keeps it.
    func observationCount(in row: AnalyticsDayRow) -> Int? {
        switch self {
        case .mood: return row.moodCount
        case .energy: return row.energyCount
        case .motivation: return row.motivationCount
        case .satiety: return row.hungerCount
        case .appetite: return row.appetiteCount
        case .activity, .rest, .work, .study: return row.sessionCount
        case .sleep: return nil
        }
    }

    private func hours(_ row: AnalyticsDayRow, _ key: String) -> Double? {
        guard let seconds = row.durationByType[key], seconds > 0 else { return nil }
        return seconds / 3600
    }

    // MARK: - Scale

    /// The vertical range for one metric, or for two that share an axis.
    static func domain(for metrics: [AnalyticsMetric], values: [Double]) -> ClosedRange<Double> {
        if metrics.allSatisfy({ $0.unit == .rating }) { return 1...5 }
        let top = values.max() ?? 0
        let rounded = (max(top, 1) / 2).rounded(.up) * 2
        return 0...max(4, rounded)
    }

    /// Two metrics may share one axis only when they are the same kind of
    /// number. Mood (1–5) and sleep (hours) never do.
    func sharesAxis(with other: AnalyticsMetric) -> Bool { unit == other.unit }

    // MARK: - Formatting

    func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch unit {
        case .rating:
            let text = String(format: "%.1f", value)
            return AppLanguage.current == .ru ? text.replacingOccurrences(of: ".", with: ",") : text
        case .hours:
            return DurationFormatting.compact(value * 3600)
        }
    }

    /// Value with its unit — "3,4 / 5", "7 ч 20 мин".
    func formatWithUnit(_ value: Double?) -> String {
        guard let value else { return "—" }
        return unit == .rating ? format(value) + " / 5" : format(value)
    }
}

// MARK: - Chart series

/// One metric's days as points, plus the runs of *consecutive* days a line
/// may be drawn through. A missing day ends a run: the line is never bridged
/// across a day nothing was recorded.
struct AnalyticsChartSeries: Identifiable, Sendable {
    struct Point: Identifiable, Sendable {
        var id: Date { day }
        let day: Date
        let value: Double
        let observations: Int?
    }

    var id: String { metric.rawValue }
    let metric: AnalyticsMetric
    let points: [Point]
    let runs: [[Point]]

    var average: Double? {
        points.isEmpty ? nil : points.reduce(0) { $0 + $1.value } / Double(points.count)
    }

    var isEmpty: Bool { points.isEmpty }

    func point(on day: Date, calendar: Calendar = .current) -> Point? {
        let start = calendar.startOfDay(for: day)
        return points.first { $0.day == start }
    }

    static func make(metric: AnalyticsMetric, days: [AnalyticsDayRow], calendar: Calendar = .current) -> AnalyticsChartSeries {
        let points = days
            .compactMap { row -> Point? in
                guard let value = metric.value(in: row) else { return nil }
                return Point(day: calendar.startOfDay(for: row.day), value: value, observations: metric.observationCount(in: row))
            }
            .sorted { $0.day < $1.day }
        return AnalyticsChartSeries(metric: metric, points: points, runs: runs(of: points, calendar: calendar))
    }

    /// Splits points wherever at least one calendar day is missing between
    /// two neighbours. A day is never "+24 h": DST days are 23 or 25 hours.
    static func runs(of points: [Point], calendar: Calendar = .current) -> [[Point]] {
        var out: [[Point]] = []
        var current: [Point] = []
        for point in points {
            if let last = current.last,
               calendar.date(byAdding: .day, value: 1, to: last.day).map({ calendar.startOfDay(for: $0) }) != point.day {
                out.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

/// How chosen metrics are laid out. Decided by units, not by taste.
enum AnalyticsChartLayout: Equatable, Sendable {
    /// One metric, or several on the same kind of scale: one plot, one axis.
    case shared
    /// Different units: one panel each, stacked on a common time axis.
    case stacked

    static func layout(for metrics: [AnalyticsMetric]) -> AnalyticsChartLayout {
        guard let first = metrics.first else { return .shared }
        return metrics.dropFirst().allSatisfy({ $0.sharesAxis(with: first) }) ? .shared : .stacked
    }
}
