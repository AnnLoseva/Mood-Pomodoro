//
//  CycleStore.swift
//  Mood Pomodoro
//

import Foundation
import Observation
import SwiftData

/// Owns writes to `CycleEntry` so views never normalize dates or dedupe
/// records themselves. Reads can still go through `@Query` for live updates —
/// this type exists for the mutations and for the day math.
///
/// Cycle data here is personal context for the user's own observations. The
/// app records only what she enters: no prediction, no phase inference, no
/// medical interpretation anywhere in this file.
@MainActor
@Observable
final class CycleStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    var entries: [CycleEntry] {
        let descriptor = FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Records an event, replacing any existing one of the same kind on that
    /// day — marking "начало" twice on one date is a correction, not a second
    /// cycle. "Начало" and "продолжается" replace each other too: a day is
    /// one or the other.
    func log(_ kind: CycleEventKind, on date: Date, note: String? = nil, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let replaces: Set<CycleEventKind> = kind == .periodEnd ? [.periodEnd] : [.periodStart, .periodDay]
        for existing in entries where replaces.contains(existing.kind) && calendar.isDate(existing.date, inSameDayAs: day) {
            context.delete(existing)
        }
        context.insert(CycleEntry(date: day, kind: kind, note: note, calendar: calendar))
        try? context.save()
    }

    /// Marks a run of days at once — "это было с 7 по 10". The first day is
    /// either the start of a period or a continuation of one already
    /// recorded; every later day is a continuation. Nothing past `last` is
    /// assumed.
    func logPeriod(
        from first: Date,
        through last: Date,
        firstDayIsStart: Bool,
        calendar: Calendar = .current
    ) {
        let start = calendar.startOfDay(for: min(first, last))
        let end = calendar.startOfDay(for: max(first, last))
        var day = start
        while day <= end {
            let kind: CycleEventKind = (day == start && firstDayIsStart) ? .periodStart : .periodDay
            for existing in entries where calendar.isDate(existing.date, inSameDayAs: day)
                && (existing.kind == .periodStart || existing.kind == .periodDay) {
                context.delete(existing)
            }
            context.insert(CycleEntry(date: day, kind: kind, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        try? context.save()
    }

    func delete(_ entry: CycleEntry) {
        context.delete(entry)
        try? context.save()
    }

    /// Removes every cycle event recorded on `date`, whatever its kind.
    func clear(on date: Date, calendar: Calendar = .current) {
        for entry in entries where calendar.isDate(entry.date, inSameDayAs: date) {
            context.delete(entry)
        }
        try? context.save()
    }

    func cycleDay(for date: Date, calendar: Calendar = .current) -> Int? {
        AnalyticsService.cycleDay(for: date, entries: entries, calendar: calendar)
    }

    func events(on date: Date, calendar: Calendar = .current) -> [CycleEventKind] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) }.map(\.kind)
    }
}
