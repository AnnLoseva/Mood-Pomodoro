//
//  DiaryEntryStore.swift
//  Mood Pomodoro
//

import Foundation
import Observation
import SwiftData

/// Owns every write the user makes straight into the diary — including
/// entries about the past. Nothing here assumes "now": each call takes the
/// moment the event actually happened, and stamps `createdAt`/`updatedAt`
/// separately. Reads stay on `@Query`, so any save here re-derives the day,
/// the month, the calendar colors and the timeline without a manual refresh.
///
/// Sync: every record is a plain SwiftData row, so CloudKit carries the
/// event date across devices unchanged. Where two devices can race on the
/// same logical slot (one support mark per day), readers pick the newest
/// `updatedAt` and writers collapse the leftovers — the same
/// last-write-wins rule `SessionManager.repairInvariants` applies to sessions.
@MainActor
@Observable
final class DiaryEntryStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Activities

    /// A finished activity typed in after the fact: one closed work segment,
    /// `.completed`, never scheduled for check-ins.
    @discardableResult
    func addManualActivity(activity: String, start: Date, end: Date, note: String? = nil) -> FocusSession {
        let session = FocusSession(activity: activity, startDate: start, checkInIntervalMinutes: 10)
        session.origin = .manual
        session.state = .completed
        session.endDate = end
        session.note = note
        session.createdAt = .now
        session.updatedAt = .now
        context.insert(session)
        let segment = SessionSegment(type: .work, startDate: start, endDate: end)
        segment.session = session
        session.segments = [segment]
        save()
        return session
    }

    func updateManualActivity(_ session: FocusSession, activity: String, start: Date, end: Date, note: String?) {
        guard session.isManualEntry else { return }
        session.activity = activity
        session.startDate = start
        session.endDate = end
        session.note = note
        // A manual entry is always exactly one work segment; rebuild it
        // rather than trying to stretch whatever sync may have left behind.
        for segment in session.segments ?? [] { context.delete(segment) }
        let segment = SessionSegment(type: .work, startDate: start, endDate: end)
        segment.session = session
        session.segments = [segment]
        session.touch()
        save()
    }

    func deleteManualActivity(_ session: FocusSession) {
        guard session.isManualEntry else { return }
        context.delete(session)
        save()
    }

    // MARK: - Mood

    @discardableResult
    func addMood(_ mood: Mood, reason: String?, note: String?, at timestamp: Date) -> CheckIn {
        let checkIn = CheckIn(timestamp: timestamp, mood: mood, reason: reason, note: note, origin: .manual)
        context.insert(checkIn)
        save()
        return checkIn
    }

    /// Works for session check-ins too — the user may correct a mood or its
    /// reason. The condition snapshot is left alone: it records what was
    /// true in the session, which moving the mood doesn't change.
    func updateMood(_ checkIn: CheckIn, mood: Mood, reason: String?, note: String?, at timestamp: Date) {
        checkIn.mood = mood
        checkIn.reason = reason
        checkIn.note = note
        checkIn.timestamp = timestamp
        checkIn.updatedAt = .now
        checkIn.session?.touch()
        save()
    }

    func deleteCheckIn(_ checkIn: CheckIn) {
        checkIn.session?.touch()
        context.delete(checkIn)
        save()
    }

    // MARK: - Daily support

    func supportEntry(on day: Date, calendar: Calendar = .current) -> SupportEntry? {
        AnalyticsService.supportEntry(on: day, entries: supportEntries(on: day, calendar: calendar), calendar: calendar)
    }

    /// Sets the one mark for `day`, editing the existing record if there is
    /// one and dropping any duplicates another device created for that day.
    func setSupport(
        _ status: SupportStatus,
        on day: Date,
        time: Date?,
        note: String?,
        calendar: Calendar = .current
    ) {
        let existing = supportEntries(on: day, calendar: calendar).sorted { $0.updatedAt > $1.updatedAt }
        let entry: SupportEntry
        if let newest = existing.first {
            entry = newest
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            entry = SupportEntry(day: day, status: status, calendar: calendar)
            context.insert(entry)
        }
        entry.status = status
        entry.time = time
        entry.note = note
        entry.updatedAt = .now
        save()
    }

    /// Back to "не отмечено" — which is not the same as "не принято".
    func clearSupport(on day: Date, calendar: Calendar = .current) {
        for entry in supportEntries(on: day, calendar: calendar) { context.delete(entry) }
        save()
    }

    private func supportEntries(on day: Date, calendar: Calendar) -> [SupportEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let key = SupportEntry.defaultTrackerKey
        let descriptor = FetchDescriptor<SupportEntry>(
            predicate: #Predicate { $0.day >= start && $0.day < end && $0.trackerKey == key }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Factors

    /// A factor recorded outside any session ("в 15:00 — пуэр").
    @discardableResult
    func addFactor(category: FactorCategory, option: FactorOption, at timestamp: Date) -> ConditionEvent {
        let event = ConditionEvent(timestamp: timestamp, category: category, option: option)
        context.insert(event)
        save()
        return event
    }

    func updateFactor(_ event: ConditionEvent, category: FactorCategory, option: FactorOption, at timestamp: Date) {
        event.timestamp = timestamp
        event.categoryID = category.id
        event.categoryName = category.name
        event.categoryIcon = category.icon
        event.categoryIconImageName = category.iconImageName
        event.optionID = option.id
        event.optionName = option.name
        event.optionIconImageName = option.iconImageName
        event.updatedAt = .now
        event.session?.touch()
        save()
    }

    func deleteFactor(_ event: ConditionEvent) {
        event.session?.touch()
        context.delete(event)
        save()
    }

    // MARK: - Notes

    @discardableResult
    func addNote(_ text: String, at timestamp: Date) -> JournalNote {
        let note = JournalNote(timestamp: timestamp, text: text)
        context.insert(note)
        save()
        return note
    }

    func updateNote(_ note: JournalNote, text: String, at timestamp: Date) {
        note.text = text
        note.timestamp = timestamp
        note.updatedAt = .now
        save()
    }

    func deleteNote(_ note: JournalNote) {
        context.delete(note)
        save()
    }

    // MARK: - Lookup by id (edit sheets receive ids, not live objects)

    func session(id: UUID) -> FocusSession? {
        try? context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })).first
    }

    func checkIn(id: UUID) -> CheckIn? {
        try? context.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == id })).first
    }

    func factor(id: UUID) -> ConditionEvent? {
        try? context.fetch(FetchDescriptor<ConditionEvent>(predicate: #Predicate { $0.id == id })).first
    }

    func note(id: UUID) -> JournalNote? {
        try? context.fetch(FetchDescriptor<JournalNote>(predicate: #Predicate { $0.id == id })).first
    }

    private func save() {
        try? context.save()
    }
}
