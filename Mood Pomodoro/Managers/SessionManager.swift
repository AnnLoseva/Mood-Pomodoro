//
//  SessionManager.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData
import Observation

/// Owns session lifecycle actions (start/pause/resume/finish/cancel) and the
/// currently active session. Views read `activeSession`; everything else
/// (scheduling reminders, cancelling them) is handled here so views stay dumb.
@MainActor
@Observable
final class SessionManager {
    private let context: ModelContext
    private(set) var activeSession: FocusSession?

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()
    }

    func refresh() {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        activeSession = try? context.fetch(descriptor).first
    }

    /// - Parameter initialConditions: the conditions picked on the New Session
    ///   screen, keyed by category. Each becomes a `ConditionEvent` stamped at
    ///   the session's start.
    func startSession(
        activity: String,
        intervalMinutes: Int,
        initialConditions: [FactorCategory: FactorOption] = [:]
    ) {
        let session = FocusSession(activity: activity, checkInIntervalMinutes: intervalMinutes)
        context.insert(session)
        for (category, option) in initialConditions {
            let event = ConditionEvent(timestamp: session.startDate, category: category, option: option)
            event.session = session
            session.conditionEvents.append(event)
        }
        try? context.save()
        activeSession = session
        Task {
            await NotificationScheduler.scheduleUpcoming(
                for: session,
                fromCheckpoint: 1,
                referenceStart: session.scheduleAnchor
            )
        }
    }

    /// Records changed conditions mid-session as new `ConditionEvent`s timestamped
    /// `now`. Only categories whose selection actually differs from what's
    /// currently active get a new event — picking the same value again is a
    /// no-op, so re-opening and closing the editor doesn't spam the timeline.
    /// Never touches existing check-ins or their stored snapshots.
    func updateConditions(_ selection: [FactorCategory: FactorOption], for session: FocusSession? = nil) {
        guard let target = session ?? activeSession else { return }
        let now = Date.now
        let currentlyActive = Dictionary(
            uniqueKeysWithValues: target.activeConditions(asOf: now).map { ($0.categoryID, $0.optionID) }
        )
        for (category, option) in selection where currentlyActive[category.id] != option.id {
            let event = ConditionEvent(timestamp: now, category: category, option: option)
            event.session = target
            target.conditionEvents.append(event)
        }
        try? context.save()
    }

    func pause() {
        guard let session = activeSession, !session.isPaused else { return }
        session.isPaused = true
        session.pausedAt = .now
        try? context.save()
        NotificationScheduler.cancelAll(for: session.id)
    }

    func resume() {
        guard let session = activeSession, session.isPaused, let pausedAt = session.pausedAt else { return }
        session.accumulatedPauseInterval += Date.now.timeIntervalSince(pausedAt)
        session.isPaused = false
        session.pausedAt = nil
        try? context.save()

        let interval = session.checkInInterval
        let elapsed = session.elapsedActiveTime()
        let nextCheckpoint = interval > 0 ? Int(elapsed / interval) + 1 : 1
        Task {
            await NotificationScheduler.scheduleUpcoming(
                for: session,
                fromCheckpoint: nextCheckpoint,
                referenceStart: session.scheduleAnchor
            )
        }
    }

    func finish() {
        guard let session = activeSession else { return }
        session.isActive = false
        session.endDate = .now
        try? context.save()
        NotificationScheduler.cancelAll(for: session.id)
        activeSession = nil
    }

    func cancel() {
        guard let session = activeSession else { return }
        NotificationScheduler.cancelAll(for: session.id)
        context.delete(session)
        try? context.save()
        activeSession = nil
    }

    func addCheckIn(mood: Mood, reason: String?, note: String? = nil, to session: FocusSession? = nil) {
        guard let target = session ?? activeSession else { return }
        let timestamp = Date.now
        let checkIn = CheckIn(
            timestamp: timestamp,
            mood: mood,
            reason: reason,
            note: note,
            conditionSnapshot: target.activeConditions(asOf: timestamp)
        )
        checkIn.session = target
        target.checkIns.append(checkIn)
        try? context.save()
    }

    /// Fills in the reason on a check-in that was created mood-only from a
    /// notification action, e.g. when the user opens the app from the
    /// "Почему так?" follow-up instead of answering it from the lock screen.
    func updateReason(_ reason: String?, for checkInID: UUID) {
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == checkInID })
        guard let checkIn = try? context.fetch(descriptor).first else { return }
        checkIn.reason = reason
        try? context.save()
    }

    func session(withID id: UUID) -> FocusSession? {
        if activeSession?.id == id { return activeSession }
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
