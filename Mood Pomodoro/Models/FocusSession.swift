//
//  FocusSession.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var activity: String
    var startDate: Date
    var endDate: Date?
    var checkInIntervalMinutes: Int
    var isActive: Bool
    var isPaused: Bool
    var pausedAt: Date?
    /// Total time spent paused so far, in seconds. Used to compute active elapsed
    /// time and to shift future check-in checkpoints when the session resumes.
    var accumulatedPauseInterval: TimeInterval

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.session)
    var checkIns: [CheckIn] = []

    init(
        id: UUID = UUID(),
        activity: String,
        startDate: Date = .now,
        checkInIntervalMinutes: Int
    ) {
        self.id = id
        self.activity = activity
        self.startDate = startDate
        self.endDate = nil
        self.checkInIntervalMinutes = checkInIntervalMinutes
        self.isActive = true
        self.isPaused = false
        self.pausedAt = nil
        self.accumulatedPauseInterval = 0
    }

    var checkInInterval: TimeInterval { TimeInterval(checkInIntervalMinutes * 60) }

    /// The anchor date check-in checkpoints are computed from. Shifts forward every
    /// time the session pauses, so reminders stay tied to active time, not wall clock.
    var scheduleAnchor: Date {
        startDate.addingTimeInterval(accumulatedPauseInterval)
    }

    /// Elapsed *active* time (excludes paused duration), as of `referenceDate`.
    func elapsedActiveTime(asOf referenceDate: Date = .now) -> TimeInterval {
        let end = endDate ?? referenceDate
        let pauseSoFar = accumulatedPauseInterval + currentPauseDuration(asOf: referenceDate)
        return max(0, end.timeIntervalSince(startDate) - pauseSoFar)
    }

    private func currentPauseDuration(asOf referenceDate: Date) -> TimeInterval {
        guard isPaused, let pausedAt else { return 0 }
        return max(0, referenceDate.timeIntervalSince(pausedAt))
    }

    var sortedCheckIns: [CheckIn] {
        checkIns.sorted { $0.timestamp < $1.timestamp }
    }
}
