//
//  SessionActivityAttributes.swift
//  Mood Pomodoro
//
//  Compiled into both the app and the widget extension — this is the one
//  contract between them for the session Live Activity. Nothing here talks
//  to SwiftData: ActivityKit is a display layer the app pushes snapshots to,
//  never a source of truth.
//

import ActivityKit
import Foundation

nonisolated struct SessionActivityAttributes: ActivityAttributes {
    /// Fixed for the lifetime of the Activity — doesn't change between updates.
    var sessionID: UUID
    var activityName: String
    var startDate: Date
    var checkInIntervalMinutes: Int

    /// Everything that *can* change while the Live Activity is running.
    ///
    /// `workStartDate`/`currentBreakStartDate` is whichever segment is
    /// currently open; `accumulatedWorkDuration`/`accumulatedBreakDuration`
    /// is the total of every *previously closed* segment of that type — not
    /// a live running total. That split lets the widget draw a self-ticking
    /// `Text(timerInterval:)` with no per-second update from the app.
    nonisolated struct ContentState: Codable, Hashable {
        var status: SessionState
        var workStartDate: Date?
        var currentBreakStartDate: Date?
        var accumulatedWorkDuration: TimeInterval
        var accumulatedBreakDuration: TimeInterval
        var lastCheckInDate: Date?
        var nextCheckInDate: Date?

        var isPaused: Bool { status == .paused }

        /// Count-up range for active work time. While working, the start is
        /// anchored so iOS can tick without the app; while paused, the range
        /// is closed so the displayed time freezes.
        var workTimerRange: ClosedRange<Date> {
            if status == .active, let workStart = workStartDate {
                let anchor = workStart.addingTimeInterval(-accumulatedWorkDuration)
                return anchor...anchor.addingTimeInterval(24 * 60 * 60)
            }
            let start = Date(timeIntervalSinceReferenceDate: 0)
            return start...start.addingTimeInterval(max(0, accumulatedWorkDuration))
        }

        var breakTimerRange: ClosedRange<Date>? {
            guard status == .paused, let breakStart = currentBreakStartDate else { return nil }
            return breakStart...breakStart.addingTimeInterval(24 * 60 * 60)
        }
    }
}
