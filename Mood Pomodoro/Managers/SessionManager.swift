//
//  SessionManager.swift
//  Mood Pomodoro
//

import CoreData
import Foundation
import Observation
import SwiftData

/// Owns session lifecycle actions (start/pause/resume/finish/cancel/delete)
/// and the currently active session. Views read `activeSession`; everything
/// else (scheduling reminders, cancelling them, Live Activity, CloudKit
/// recovery) is handled here so views stay dumb.
@MainActor
@Observable
final class SessionManager {
    private let context: ModelContext
    @ObservationIgnored
    private var remoteChangeObservers: [NSObjectProtocol] = []

    private(set) var activeSession: FocusSession?
    /// Bumped on every refresh so SwiftUI rebuilds even when CloudKit mutates
    /// the same `FocusSession` instance in place.
    private(set) var revision: UInt64 = 0

    /// Unit tests deallocate their in-memory store as soon as the test
    /// returns; a trailing `Task` that still holds a `FocusSession` then
    /// traps. Skip Live Activity / notification I/O under XCTest.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init(container: ModelContainer) {
        self.context = container.mainContext
        refresh()
        if !Self.isRunningTests {
            observeRemoteChanges()
        }
    }

    deinit {
        for observer in remoteChangeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Re-reads whichever session currently occupies the active/paused slot
    /// from SwiftData after launch, a background action, or a CloudKit
    /// import. CloudKit is the remote source of truth; this cache is how
    /// this device renders the shared session.
    func refresh() {
        FactorSeeder.dedupeCategories(in: context)
        deduplicateScheduledCheckIns()
        ReasonsStore.shared.reloadFromSwiftData()

        let previousID = activeSession?.id
        let previousState = activeSession?.state

        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        repairInvariants(in: all)
        let found = all.first { $0.isActive }

        activeSession = found
        revision += 1

        if let previousID, found?.id != previousID {
            NotificationScheduler.cancelAll(for: previousID)
            if !Self.isRunningTests {
                Task { await LiveActivityController.end(sessionID: previousID) }
            }
        }

        if found == nil, previousID != nil {
            // Remote End/Cancel: this device had an in-flight session that
            // another device finished.
            if let previousID {
                NotificationScheduler.cancelAll(for: previousID)
            }
        }

        if let session = found {
            if session.state == .paused {
                NotificationScheduler.cancelAll(for: session.id)
            }
            guard !Self.isRunningTests else { return }
            Task { await LiveActivityController.syncIfNeeded(with: session) }
            if session.state == .active, previousState != .active || previousID != session.id {
                Task { await NotificationScheduler.topUpIfNeeded(for: session) }
            }
        }
    }

    /// - Parameter initialConditions: the conditions picked on the New Session
    ///   screen, keyed by category. Each becomes a `ConditionEvent` stamped at
    ///   the session's start.
    func startSession(
        activity: String,
        intervalMinutes: Int,
        initialConditions: [FactorCategory: FactorOption] = [:]
    ) {
        // Another device may already have an in-flight session — don't start
        // a second one on top of it.
        refresh()
        if activeSession != nil { return }

        let session = FocusSession(activity: activity, checkInIntervalMinutes: intervalMinutes)
        context.insert(session)
        let workSegment = SessionSegment(type: .work, startDate: session.startDate)
        workSegment.session = session
        session.segments = (session.segments ?? []) + [workSegment]
        for (category, option) in initialConditions {
            let event = ConditionEvent(timestamp: session.startDate, category: category, option: option)
            event.session = session
            session.conditionEvents = (session.conditionEvents ?? []) + [event]
        }
        session.touch()
        try? context.save()
        activeSession = session
        revision += 1
        guard !Self.isRunningTests else { return }
        NotificationScheduler.registerCategories(reasons: ReasonsStore.shared.reasons)
        Task {
            await NotificationScheduler.scheduleUpcoming(
                for: session,
                fromCheckpoint: 1,
                referenceStart: session.scheduleAnchor
            )
            await LiveActivityController.start(for: session)
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
            target.conditionEvents = (target.conditionEvents ?? []) + [event]
        }
        target.touch()
        try? context.save()
        revision += 1
    }

    func pause(sessionID: UUID? = nil) {
        guard let session = resolve(sessionID), session.state == .active else { return }
        let now = Date.now
        if let current = session.currentSegment, current.type == .work {
            current.endDate = now
        }
        let breakSegment = SessionSegment(type: .pause, startDate: now)
        breakSegment.session = session
        session.segments = (session.segments ?? []) + [breakSegment]
        session.state = .paused
        session.touch(at: now)
        try? context.save()
        activeSession = session
        revision += 1
        NotificationScheduler.cancelAll(for: session.id)
        guard !Self.isRunningTests else { return }
        Task { await LiveActivityController.update(for: session) }
    }

    func resume(sessionID: UUID? = nil) {
        guard let session = resolve(sessionID), session.state == .paused else { return }
        let now = Date.now
        if let current = session.currentSegment, current.type == .pause {
            current.endDate = now
        }
        let workSegment = SessionSegment(type: .work, startDate: now)
        workSegment.session = session
        session.segments = (session.segments ?? []) + [workSegment]
        session.state = .active
        session.touch(at: now)
        try? context.save()
        activeSession = session
        revision += 1

        let interval = session.checkInInterval
        let elapsed = session.elapsedActiveTime()
        let nextCheckpoint = interval > 0 ? Int(elapsed / interval) + 1 : 1
        guard !Self.isRunningTests else { return }
        Task {
            await NotificationScheduler.scheduleUpcoming(
                for: session,
                fromCheckpoint: nextCheckpoint,
                referenceStart: session.scheduleAnchor
            )
            await LiveActivityController.update(for: session)
        }
    }

    func finish(sessionID: UUID? = nil) {
        guard let session = resolve(sessionID), session.isActive else { return }
        let now = Date.now
        if let current = session.currentSegment {
            current.endDate = now
        }
        session.state = .completed
        session.endDate = now
        session.touch(at: now)
        try? context.save()
        NotificationScheduler.cancelAll(for: session.id)
        if !Self.isRunningTests {
            Task { await LiveActivityController.end(for: session) }
        }
        if activeSession?.id == session.id {
            activeSession = nil
        }
        revision += 1
    }

    /// Cancel ≠ End: the session is discarded outright rather than kept as a
    /// completed session with a short duration, matching the app's existing
    /// cancel behavior from before segments existed.
    func cancel(sessionID: UUID? = nil) {
        guard let session = resolve(sessionID) else { return }
        NotificationScheduler.cancelAll(for: session.id)
        if !Self.isRunningTests {
            Task { await LiveActivityController.end(for: session) }
        }
        let id = session.id
        context.delete(session)
        try? context.save()
        if activeSession?.id == id {
            activeSession = nil
        }
        revision += 1
    }

    /// Permanently removes a session (test runs, mistakes) so it cannot
    /// affect history or analytics. If it was the in-flight session, also
    /// tears down notifications and the Live Activity.
    func delete(_ session: FocusSession) {
        NotificationScheduler.cancelAll(for: session.id)
        if !Self.isRunningTests {
            Task { await LiveActivityController.end(for: session) }
        }
        let id = session.id
        context.delete(session)
        try? context.save()
        if activeSession?.id == id {
            activeSession = nil
        }
        revision += 1
    }

    func addCheckIn(
        mood: Mood,
        reason: String? = nil,
        note: String? = nil,
        to session: FocusSession? = nil,
        sourceIdentifier: String? = nil,
        occurrenceID: String? = nil,
        scheduledAt: Date? = nil,
        origin: CheckInOrigin = .manual
    ) {
        guard let target = session ?? activeSession, target.state == .active else { return }
        let timestamp = Date.now
        if let occurrenceID {
            let existing = (target.checkIns ?? []).contains { $0.occurrenceID == occurrenceID }
            if existing { return }
        }
        if let last = target.sortedCheckIns.last,
           last.mood == mood,
           timestamp.timeIntervalSince(last.timestamp) < 2 {
            return
        }
        let checkIn = CheckIn(
            timestamp: timestamp,
            mood: mood,
            reason: reason,
            note: note,
            conditionSnapshot: target.activeConditions(asOf: timestamp),
            sourceIdentifier: sourceIdentifier,
            occurrenceID: occurrenceID,
            scheduledAt: scheduledAt,
            origin: origin
        )
        checkIn.session = target
        target.checkIns = (target.checkIns ?? []) + [checkIn]
        target.touch(at: timestamp)
        try? context.save()
        revision += 1
        guard !Self.isRunningTests else { return }
        Task {
            await LiveActivityController.update(for: target)
            if sourceIdentifier != nil {
                await NotificationScheduler.scheduleReasonPrompt(
                    sessionID: target.id,
                    checkInID: checkIn.id,
                    mood: mood,
                    reasons: ReasonsStore.shared.reasons(for: mood)
                )
            }
        }
    }

    /// Fills in the reason on a check-in that was created mood-only from a
    /// notification action, e.g. when the user opens the app from the
    /// "Почему так?" follow-up instead of answering it from the lock screen.
    func updateReason(_ reason: String?, for checkInID: UUID) {
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == checkInID })
        guard let checkIn = try? context.fetch(descriptor).first else { return }
        checkIn.reason = reason
        checkIn.session?.touch()
        try? context.save()
        revision += 1
    }

    func session(withID id: UUID) -> FocusSession? {
        if activeSession?.id == id { return activeSession }
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func recordMoodFromLiveActivity(sessionID: UUID, moodRaw: String) {
        guard let mood = Mood(rawValue: moodRaw) else { return }
        guard let session = session(withID: sessionID) else { return }
        addCheckIn(
            mood: mood,
            to: session,
            sourceIdentifier: "liveactivity.\(sessionID.uuidString).\(moodRaw).\(Int(Date.now.timeIntervalSince1970))"
        )
    }

    private func resolve(_ sessionID: UUID?) -> FocusSession? {
        if let sessionID {
            return session(withID: sessionID)
        }
        return activeSession
    }

    /// After a CloudKit merge, scheduled check-ins for the same occurrence
    /// can exist twice (each device answered the same 10:10 ping). Keep the
    /// earliest; drop the rest. Manual check-ins have a nil occurrenceID
    /// and are never collapsed.
    private func deduplicateScheduledCheckIns() {
        let descriptor = FetchDescriptor<CheckIn>()
        let all = (try? context.fetch(descriptor)) ?? []
        var seen: [String: CheckIn] = [:]
        var duplicates: [CheckIn] = []
        for checkIn in all {
            guard let occurrenceID = checkIn.occurrenceID else { continue }
            if let existing = seen[occurrenceID] {
                let loser = checkIn.timestamp < existing.timestamp ? existing : checkIn
                let winner = loser.id == existing.id ? checkIn : existing
                seen[occurrenceID] = winner
                duplicates.append(loser)
            } else {
                seen[occurrenceID] = checkIn
            }
        }
        guard !duplicates.isEmpty else { return }
        for duplicate in duplicates { context.delete(duplicate) }
        try? context.save()
    }

    /// CloudKit last-write-wins can leave a completed session with an open
    /// segment, or two in-flight sessions. Close leftovers; if two sessions
    /// claim to be active, keep the newest `updatedAt`.
    private func repairInvariants(in sessions: [FocusSession]) {
        for session in sessions where session.state == .completed || session.state == .cancelled {
            if let current = session.currentSegment {
                current.endDate = session.endDate ?? Date.now
            }
        }
        let inFlight = sessions.filter(\.isActive)
        guard inFlight.count > 1 else { return }
        let keep = inFlight.max { $0.updatedAt < $1.updatedAt }
        for extra in inFlight where extra.id != keep?.id {
            extra.state = .completed
            extra.endDate = extra.endDate ?? extra.updatedAt
            if let current = extra.currentSegment {
                current.endDate = extra.endDate
            }
        }
        try? context.save()
    }

    private func observeRemoteChanges() {
        let center = NotificationCenter.default
        remoteChangeObservers.append(
            center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        )
        remoteChangeObservers.append(
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        )
    }
}
