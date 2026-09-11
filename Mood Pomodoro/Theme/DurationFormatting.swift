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
        if hours > 0 { return L("\(hours)ч \(minutes)м", "\(hours)h \(minutes)m") }
        return L("\(minutes)м", "\(minutes)m")
    }
}

/// Locale-aware date/time strings. Persistence always stores `Date`;
/// these formatters are UI-only.
enum DateFormatting {
    /// Dates follow the app's language, not the device's — an English diary
    /// on a Russian phone still says "September".
    private static var locale: Locale { AppLanguage.current.locale }

    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    static func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    static func timeRange(from start: Date, to end: Date?) -> String {
        "\(time(start)) — \(end.map(time) ?? "…")"
    }

    static func historySectionTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return L("Сегодня", "Today") }
        if calendar.isDateInYesterday(day) { return L("Вчера", "Yesterday") }
        return fullDate(day)
    }

    static func isSameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
