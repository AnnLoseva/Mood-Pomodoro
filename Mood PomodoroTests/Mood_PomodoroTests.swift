//
//  Mood_PomodoroTests.swift
//  Mood PomodoroTests
//

import Foundation
import Testing
@testable import Mood_Pomodoro

struct Mood_PomodoroTests {

    @Test func elapsedActiveTimeExcludesPauses() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)

        // 20 minutes of wall-clock time, but 5 of those were paused.
        session.accumulatedPauseInterval = 5 * 60
        let asOf = start.addingTimeInterval(20 * 60)

        #expect(session.elapsedActiveTime(asOf: asOf) == 15 * 60)
    }

    @Test func elapsedActiveTimeIncludesOngoingPause() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        session.isPaused = true
        session.pausedAt = start.addingTimeInterval(10 * 60)

        let asOf = start.addingTimeInterval(15 * 60)
        // 10 minutes active before the pause, then 5 minutes paused so far.
        #expect(session.elapsedActiveTime(asOf: asOf) == 10 * 60)
    }

    @Test func scheduleAnchorShiftsByAccumulatedPause() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        session.accumulatedPauseInterval = 90

        #expect(session.scheduleAnchor == start.addingTimeInterval(90))
    }

    @Test func moodActionIdentifierRoundTrips() {
        for mood in Mood.allCases {
            let identifier = NotificationScheduler.actionIdentifier(for: mood)
            #expect(NotificationScheduler.mood(fromActionIdentifier: identifier) == mood)
        }
    }
}
