//
//  LiveActivityController.swift
//  Mood Pomodoro
//
//  Pushes SwiftData state into ActivityKit and never reads anything back
//  out of it — the Live Activity is a mirror, not a database. Every call is
//  a no-op if Live Activities aren't available so tracking itself never
//  depends on it.
//

import ActivityKit
import Foundation

@MainActor
enum LiveActivityController {
    private static func contentState(for session: FocusSession) -> SessionActivityAttributes.ContentState {
        let segments = session.segments ?? []
        let currentWork = segments.first { $0.type == .work && $0.endDate == nil }
        let currentBreak = segments.first { $0.type == .pause && $0.endDate == nil }
        let closedWork = segments.filter { $0.type == .work && $0.endDate != nil }.reduce(0) { $0 + $1.duration() }
        let closedBreak = segments.filter { $0.type == .pause && $0.endDate != nil }.reduce(0) { $0 + $1.duration() }
        return SessionActivityAttributes.ContentState(
            status: session.state,
            workStartDate: currentWork?.startDate,
            currentBreakStartDate: currentBreak?.startDate,
            accumulatedWorkDuration: closedWork,
            accumulatedBreakDuration: closedBreak,
            lastCheckInDate: session.sortedCheckIns.last?.timestamp,
            nextCheckInDate: session.state == .active ? nextCheckInDate(for: session) : nil
        )
    }

    private static func nextCheckInDate(for session: FocusSession) -> Date? {
        let interval = session.checkInInterval
        guard interval > 0 else { return nil }
        let elapsed = session.elapsedActiveTime()
        let nextCheckpoint = Int(elapsed / interval) + 1
        return session.scheduleAnchor.addingTimeInterval(interval * Double(nextCheckpoint))
    }

    private static func existingActivity(for sessionID: UUID) -> Activity<SessionActivityAttributes>? {
        Activity<SessionActivityAttributes>.activities.first { $0.attributes.sessionID == sessionID }
    }

    /// Starts a fresh Live Activity, or just updates one that's already
    /// running for this session (e.g. a stray re-entrant call).
    static func start(for session: FocusSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = existingActivity(for: session.id) {
            await existing.update(ActivityContent(state: contentState(for: session), staleDate: nil))
            return
        }
        let attributes = SessionActivityAttributes(
            sessionID: session.id,
            activityName: Ldata(session.activity),
            startDate: session.startDate,
            checkInIntervalMinutes: session.checkInIntervalMinutes,
            languageCode: AppLanguage.current.rawValue
        )
        let content = ActivityContent(state: contentState(for: session), staleDate: nil)
        do {
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            // No Live Activity this run (disabled in Settings, unsupported
            // device, etc.) — session tracking via SwiftData + notifications
            // keeps working regardless.
        }
    }

    static func update(for session: FocusSession) async {
        guard let activity = existingActivity(for: session.id) else { return }
        await activity.update(ActivityContent(state: contentState(for: session), staleDate: nil))
    }

    static func end(for session: FocusSession) async {
        guard let activity = existingActivity(for: session.id) else { return }
        await activity.end(ActivityContent(state: contentState(for: session), staleDate: nil), dismissalPolicy: .immediate)
    }

    static func end(sessionID: UUID) async {
        guard let activity = existingActivity(for: sessionID) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// Called whenever `SessionManager` re-discovers an ongoing session (app
    /// launch/foreground, CloudKit import). Recreates the Activity if none
    /// is running, or catches an existing one up to current data.
    static func syncIfNeeded(with session: FocusSession) async {
        if existingActivity(for: session.id) != nil {
            await update(for: session)
        } else if session.isActive {
            await start(for: session)
        }
    }
}
