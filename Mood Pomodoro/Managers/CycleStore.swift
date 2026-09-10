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
    /// cycle.
    func log(_ kind: CycleEventKind, on date: Date, note: String? = nil, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        for existing in entries where existing.kind == kind && calendar.isDate(existing.date, inSameDayAs: day) {
            context.delete(existing)
        }
        context.insert(CycleEntry(date: day, kind: kind, note: note, calendar: calendar))
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
