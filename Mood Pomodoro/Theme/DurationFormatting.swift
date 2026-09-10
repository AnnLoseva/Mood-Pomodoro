//
//  DurationFormatting.swift
//  Mood Pomodoro
//

import Foundation

enum DurationFormatting {
    static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)ч \(minutes)м" }
        return "\(minutes)м"
    }
}

/// Locale-aware date/time strings. Persistence always stores `Date`;
/// these formatters are UI-only.
enum DateFormatting {
    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    static func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func timeRange(from start: Date, to end: Date?) -> String {
        "\(time(start)) — \(end.map(time) ?? "…")"
    }

    static func historySectionTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Сегодня" }
        if calendar.isDateInYesterday(day) { return "Вчера" }
        return fullDate(day)
    }

    static func isSameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
