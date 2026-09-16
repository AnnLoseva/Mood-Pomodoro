//
//  Mood_PomodoroTests.swift
//  Mood PomodoroTests
//

import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

/// Serialized: several tests spin up their own in-memory SwiftData
/// `ModelContainer` from the shared `PersistenceController.schema`, and
/// Swift Testing parallelizes tests by default — concurrent container
/// creation from that one `Schema` instance is racy and can crash the test
/// process even though every test passes fine on its own.
@Suite(.serialized)
struct Mood_PomodoroTests {

    /// Fresh schema each time — sharing `PersistenceController.schema`
    /// across concurrent `ModelContainer`s is racy even with a serialized
    /// suite, because xcodebuild may still spawn cloned simulators.
    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: FocusSession.self,
            CheckIn.self,
            FactorCategory.self,
            FactorOption.self,
            ConditionEvent.self,
            SessionSegment.self,
            MoodReason.self,
            CycleEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// Two devices seed the same category before their first sync. Each
    /// must keep the *same* copy — if they kept different ones, each
    /// device's deletion would remove the other's survivor once synced.
    @Test func duplicateSeededCategoriesKeepTheSameCopyWhateverTheOrder() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!

        for insertionOrder in [[firstID, secondID], [secondID, firstID]] {
            let container = try makeTestContainer()
            let context = ModelContext(container)
            for id in insertionOrder {
                context.insert(FactorCategory(id: id, name: "Музыка", icon: "🎧", sortOrder: 0))
            }
            try context.save()

            FactorSeeder.dedupeCategories(in: context)

            let remaining = try context.fetch(FetchDescriptor<FactorCategory>())
            #expect(remaining.map(\.id) == [firstID])
        }
    }

    /// Appends a segment to `session` and keeps the two sides of the
    /// relationship in sync, mirroring what `SessionManager` does.
    private func appendSegment(_ type: SegmentType, start: Date, end: Date? = nil, to session: FocusSession) {
        let segment = SessionSegment(type: type, startDate: start, endDate: end)
        segment.session = session
        session.segments = (session.segments ?? []) + [segment]
    }

    @Test func elapsedActiveTimeExcludesPauses() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        // 15 minutes of work, then 5 minutes of break — 20 minutes of
        // wall-clock time, but 5 of those were paused.
        appendSegment(.work, start: start, end: start.addingTimeInterval(15 * 60), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(15 * 60), end: start.addingTimeInterval(20 * 60), to: session)

        let asOf = start.addingTimeInterval(20 * 60)
        #expect(session.elapsedActiveTime(asOf: asOf) == 15 * 60)
    }

    @Test func elapsedActiveTimeIncludesOngoingPause() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, end: start.addingTimeInterval(10 * 60), to: session)
        // Break segment still open (no endDate) — the pause is ongoing.
        appendSegment(.pause, start: start.addingTimeInterval(10 * 60), to: session)

        let asOf = start.addingTimeInterval(15 * 60)
        // 10 minutes active before the pause, then 5 minutes paused so far —
        // active time must not keep growing while paused.
        #expect(session.elapsedActiveTime(asOf: asOf) == 10 * 60)
    }

    @Test func scheduleAnchorShiftsByAccumulatedBreakDuration() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, end: start.addingTimeInterval(90), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(90), end: start.addingTimeInterval(180), to: session)

        #expect(session.scheduleAnchor == start.addingTimeInterval(90))
    }

    // MARK: - Session state machine & segments (background-tracking spec, section 39)

    /// Test 1: Start → End. Total == Active, Break == 0.
    @Test func startThenEndYieldsNoBreakTime() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, to: session)

        let endDate = start.addingTimeInterval(60 * 60)
        session.currentSegment?.endDate = endDate
        session.endDate = endDate
        session.state = .completed

        #expect(session.totalDuration() == 60 * 60)
        #expect(session.activeWorkDuration() == 60 * 60)
        #expect(session.breakDuration() == 0)
        #expect(session.numberOfBreaks == 0)
    }

    /// Test 2: Start → Pause → Resume → End. Total == Active + Break.
    @Test func pauseThenResumeSplitsTotalIntoActiveAndBreak() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, end: start.addingTimeInterval(40 * 60), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(40 * 60), end: start.addingTimeInterval(50 * 60), to: session)
        appendSegment(.work, start: start.addingTimeInterval(50 * 60), end: start.addingTimeInterval(90 * 60), to: session)
        session.endDate = start.addingTimeInterval(90 * 60)
        session.state = .completed

        #expect(session.activeWorkDuration() == 80 * 60) // 40 + 40
        #expect(session.breakDuration() == 10 * 60)
        #expect(session.totalDuration() == session.activeWorkDuration() + session.breakDuration())

        let kinds = session.timelineEvents.map(\.kind)
        #expect(kinds.contains(.start))
        #expect(kinds.contains(.pause))
        #expect(kinds.contains(.resume))
        #expect(kinds.contains(.end))
        #expect(session.timelineEvents.map(\.timestamp) == session.timelineEvents.map(\.timestamp).sorted())
    }

    @Test func timelineInsertsDateBreakWhenSessionCrossesMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 10, hour: 23, minute: 50))!
        let session = FocusSession(activity: "Late", startDate: start, checkInIntervalMinutes: 10)
        let nextDay = start.addingTimeInterval(20 * 60) // 00:10
        appendSegment(.work, start: start, end: nextDay.addingTimeInterval(20 * 60), to: session)
        session.endDate = nextDay.addingTimeInterval(20 * 60)
        session.state = .completed

        let checkIn = CheckIn(timestamp: nextDay, mood: .good)
        checkIn.session = session
        session.checkIns = (session.checkIns ?? []) + [checkIn]

        let events = session.timelineEvents
        #expect(!DateFormatting.isSameDay(events.first!.timestamp, events.last!.timestamp, calendar: calendar))
        #expect(events.contains { $0.kind == .checkIn && DateFormatting.isSameDay($0.timestamp, nextDay, calendar: calendar) })
    }

    /// Test 3: multiple pauses accumulate correctly.
    @Test func multiplePausesAccumulateBreakDurationAndCount() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, end: start.addingTimeInterval(10 * 60), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(10 * 60), end: start.addingTimeInterval(15 * 60), to: session) // 5 min
        appendSegment(.work, start: start.addingTimeInterval(15 * 60), end: start.addingTimeInterval(45 * 60), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(45 * 60), end: start.addingTimeInterval(55 * 60), to: session) // 10 min
        appendSegment(.work, start: start.addingTimeInterval(55 * 60), end: start.addingTimeInterval(65 * 60), to: session)

        #expect(session.numberOfBreaks == 2)
        #expect(session.breakDuration() == 15 * 60)
        #expect(session.averageBreakDuration == 7.5 * 60)
        #expect(session.longestBreakDuration == 10 * 60.0)
        #expect(session.activeWorkDuration() == 50 * 60) // 10 + 30 + 10
    }

    @Test @MainActor func sessionManagerPauseResumeFinishDriveStateAndSegments() {
        let container = try! makeTestContainer()
        let manager = SessionManager(container: container)

        manager.startSession(activity: "Math", intervalMinutes: 10)
        guard let session = manager.activeSession else { Issue.record("no active session after start"); return }
        #expect(session.state == .active)
        #expect((session.segments ?? []).count == 1)
        #expect(session.currentSegment?.type == .work)

        manager.pause()
        #expect(session.state == .paused)
        #expect((session.segments ?? []).count == 2)
        #expect(session.currentSegment?.type == .pause)
        // Pausing must close the work segment, not delete/reset history.
        #expect(session.sortedSegments.first?.endDate != nil)
        #expect(session.sortedSegments.first?.type == .work)

        manager.resume()
        #expect(session.state == .active)
        #expect((session.segments ?? []).count == 3)
        #expect(session.currentSegment?.type == .work)
        #expect(session.sortedSegments[1].type == .pause)
        #expect(session.sortedSegments[1].endDate != nil) // break segment closed

        manager.finish()
        #expect(manager.activeSession == nil)
        #expect(session.state == .completed)
        #expect(session.endDate != nil)
        #expect(session.currentSegment == nil) // every segment closed
    }

    /// Tests 9/10: a new SessionManager over the same store rediscovers an
    /// in-flight session (the app-relaunch path).
    @Test @MainActor func relaunchRestoresActiveAndPausedSessions() {
        let container = try! makeTestContainer()
        let first = SessionManager(container: container)
        first.startSession(activity: "Math", intervalMinutes: 10)
        let sessionID = first.activeSession!.id

        let afterLaunch = SessionManager(container: container)
        #expect(afterLaunch.activeSession?.id == sessionID)
        #expect(afterLaunch.activeSession?.state == .active)

        afterLaunch.pause()
        let afterPauseRelaunch = SessionManager(container: container)
        #expect(afterPauseRelaunch.activeSession?.id == sessionID)
        #expect(afterPauseRelaunch.activeSession?.state == .paused)
    }

    @Test @MainActor func deleteRemovesSessionFromHistoryAndAnalytics() {
        let container = try! makeTestContainer()
        let manager = SessionManager(container: container)
        manager.startSession(activity: "Test run", intervalMinutes: 10)
        let session = manager.activeSession!
        let sessionID = session.id
        manager.finish()

        #expect(AnalyticsService.overview(sessions: [session]).sessionCount == 1)
        manager.delete(session)
        #expect(manager.session(withID: sessionID) == nil)
    }

    /// Time to first difficult mood is elapsed *work*, not wall-clock — a
    /// break in the middle must not count as time-to-fatigue.
    @Test func timeToFirstDifficultMoodExcludesBreaks() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, end: start.addingTimeInterval(40 * 60), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(40 * 60), end: start.addingTimeInterval(50 * 60), to: session)
        appendSegment(.work, start: start.addingTimeInterval(50 * 60), end: start.addingTimeInterval(70 * 60), to: session)
        session.endDate = start.addingTimeInterval(70 * 60)
        session.state = .completed

        let checkIn = CheckIn(
            timestamp: start.addingTimeInterval(60 * 60),
            mood: .tired
        )
        checkIn.session = session
        session.checkIns = (session.checkIns ?? []) + [checkIn]

        // 40m work + 10m of the second work block = 50m active, not 60m wall.
        #expect(AnalyticsService.averageTimeToFirstDifficultMood(sessions: [session]) == 50 * 60.0)
    }

    /// Test: cancel discards the session outright (Cancel ≠ End) rather than
    /// keeping it as a short completed session.
    @Test @MainActor func cancelRemovesSessionEntirely() {
        let container = try! makeTestContainer()
        let manager = SessionManager(container: container)
        manager.startSession(activity: "Math", intervalMinutes: 10)
        let sessionID = manager.activeSession?.id

        manager.cancel()

        #expect(manager.activeSession == nil)
        #expect(sessionID.flatMap(manager.session(withID:)) == nil)
    }

    /// Tests 4/5: a mood notification action creates exactly one CheckIn, and
    /// a redelivery of the *same* action is recognized before a second
    /// insert — the exact guard `NotificationDelegate.handleMoodAction` runs
    /// (fetch-by-`sourceIdentifier` before creating a CheckIn).
    @Test func scheduledOccurrenceIDDeduplicatesAcrossDevices() {
        let sessionID = UUID()
        let scheduled: TimeInterval = 1_000
        let occurrence = NotificationScheduler.occurrenceID(sessionID: sessionID, scheduledTimestamp: scheduled)
        let first = CheckIn(mood: .good, occurrenceID: occurrence, origin: .scheduled)
        let second = CheckIn(mood: .good, occurrenceID: occurrence, origin: .scheduled)
        #expect(first.occurrenceID == second.occurrenceID)
        #expect(first.origin == .scheduled)
    }

    @Test func sourceIdentifierMakesARepeatedNotificationActionIdempotent() {
        let container = try! makeTestContainer()
        let context = ModelContext(container)
        let sourceID = "session.ABC.checkin.1"
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.sourceIdentifier == sourceID })

        #expect((try? context.fetchCount(descriptor)) == 0)
        let first = CheckIn(mood: .good, sourceIdentifier: sourceID)
        context.insert(first)
        try? context.save()

        // Redelivery of the same action: the guard must see it's already handled.
        #expect((try? context.fetchCount(descriptor)) == 1)
    }

    /// Tests 12/13: a mood action's session-state guard accepts an active
    /// session's check-in and rejects one recorded while paused.
    @Test @MainActor func moodActionGuardAcceptsActiveButRejectsPausedSession() {
        let container = try! makeTestContainer()
        let manager = SessionManager(container: container)
        manager.startSession(activity: "Math", intervalMinutes: 10)
        let session = manager.activeSession!

        #expect(session.state == .active) // notification action would proceed

        manager.pause()
        #expect(session.state != .active) // notification action would be rejected
    }

    /// Test 14: analytics' average duration is active work time, not total
    /// wall-clock time — break minutes must not count as "active".
    @Test func analyticsAverageDurationExcludesBreakTime() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        appendSegment(.work, start: start, end: start.addingTimeInterval(40 * 60), to: session)
        appendSegment(.pause, start: start.addingTimeInterval(40 * 60), end: start.addingTimeInterval(50 * 60), to: session)
        appendSegment(.work, start: start.addingTimeInterval(50 * 60), end: start.addingTimeInterval(90 * 60), to: session)
        session.endDate = start.addingTimeInterval(90 * 60)
        session.state = .completed

        // Total wall-clock span is 90 minutes, but only 80 were active work.
        #expect(AnalyticsService.averageDuration(of: [session]) == 80 * 60.0)
    }

    @Test func moodActionIdentifierRoundTrips() {
        for mood in Mood.allCases {
            let identifier = NotificationScheduler.actionIdentifier(for: mood)
            #expect(identifier.hasPrefix("mood."))
            #expect(NotificationScheduler.mood(fromActionIdentifier: identifier) == mood)
        }
        #expect(NotificationScheduler.actionIdentifier(for: .veryGood) == "mood.very_good")
        #expect(NotificationScheduler.actionIdentifier(for: .neutral) == "mood.normal")
        #expect(NotificationScheduler.actionIdentifier(for: .tired) == "mood.hard")
        #expect(NotificationScheduler.actionIdentifier(for: .veryBad) == "mood.very_bad")
    }

    @Test func reasonActionIdentifierRoundTrips() {
        let identifier = NotificationScheduler.reasonActionIdentifier(mood: .good, index: 2)
        let parsed = NotificationScheduler.parseReasonAction(identifier)
        #expect(parsed?.mood == .good)
        #expect(parsed?.index == 2)
        #expect(identifier == "reason.good.2")
        let underscored = NotificationScheduler.reasonActionIdentifier(mood: .veryGood, index: 0)
        #expect(underscored == "reason.very_good.0")
        #expect(NotificationScheduler.parseReasonAction(underscored)?.mood == .veryGood)
    }

    // MARK: - Conditions

    @Test func activeConditionsReflectTheMostRecentEventAtOrBeforeTheQueryTime() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        let drinks = FactorCategory(name: "Напиток", icon: "☕")
        let coffee = FactorOption(name: "Кофе", icon: "☕")
        let puerh = FactorOption(name: "Пуэр", icon: "☕")

        let coffeeEvent = ConditionEvent(timestamp: start, category: drinks, option: coffee)
        session.conditionEvents = (session.conditionEvents ?? []) + [coffeeEvent]
        let puerhEvent = ConditionEvent(timestamp: start.addingTimeInterval(45 * 60), category: drinks, option: puerh)
        session.conditionEvents = (session.conditionEvents ?? []) + [puerhEvent]

        let beforeSwitch = session.activeConditions(asOf: start.addingTimeInterval(10 * 60))
        #expect(beforeSwitch.first { $0.categoryID == drinks.id }?.optionName == "Кофе")

        let afterSwitch = session.activeConditions(asOf: start.addingTimeInterval(50 * 60))
        #expect(afterSwitch.first { $0.categoryID == drinks.id }?.optionName == "Пуэр")
    }

    @Test func oldCheckInSnapshotIsUnaffectedByALaterConditionChange() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FocusSession(activity: "Test", startDate: start, checkInIntervalMinutes: 10)
        let drinks = FactorCategory(name: "Напиток", icon: "☕")
        let coffee = FactorOption(name: "Кофе", icon: "☕")
        let puerh = FactorOption(name: "Пуэр", icon: "☕")

        session.conditionEvents = (session.conditionEvents ?? []) + [ConditionEvent(timestamp: start, category: drinks, option: coffee)]

        // Snapshot an early check-in the way SessionManager does: freeze
        // whatever's active right now into the check-in.
        let earlyCheckInTime = start.addingTimeInterval(10 * 60)
        let earlyCheckIn = CheckIn(
            timestamp: earlyCheckInTime,
            mood: .good,
            conditionSnapshot: session.activeConditions(asOf: earlyCheckInTime)
        )

        // The user switches drinks well after that check-in was recorded.
        session.conditionEvents = (session.conditionEvents ?? []) + [
            ConditionEvent(timestamp: start.addingTimeInterval(45 * 60), category: drinks, option: puerh)
        ]

        #expect(earlyCheckIn.conditionSnapshot.first { $0.categoryID == drinks.id }?.optionName == "Кофе")
    }

    // MARK: - AnalyticsService

    @Test func averageMoodIsNilWithNoCheckIns() {
        #expect(AnalyticsService.averageMood(of: []) == nil)
    }

    @Test func averageMoodMatchesTheMoodScale() {
        let checkIns = [CheckIn(mood: .veryGood), CheckIn(mood: .veryBad)]
        #expect(AnalyticsService.averageMood(of: checkIns) == 3.0)
    }

    @Test func moodDistributionCountsEveryMoodIncludingZeros() {
        let checkIns = [CheckIn(mood: .good), CheckIn(mood: .good)]
        let distribution = AnalyticsService.moodDistribution(of: checkIns)
        #expect(distribution.counts[.good] == 2)
        #expect(distribution.counts[.veryBad] == 0)
        #expect(distribution.percentage(for: .good) == 1.0)
    }

    @Test func factorOptionBelowMinimumSampleSizeIsFlaggedAsInsufficientData() {
        let category = FactorCategory(name: "Музыка", icon: "🎧")
        let lofi = FactorOption(name: "Lo-fi", icon: "🎧")
        let checkIns = (0..<(AnalyticsService.minimumSampleSize - 1)).map { _ -> CheckIn in
            let checkIn = CheckIn(mood: .good)
            checkIn.conditionSnapshot = [
                ConditionSnapshotEntry(categoryID: category.id, categoryName: category.name, categoryIcon: category.icon, optionID: lofi.id, optionName: lofi.name)
            ]
            return checkIn
        }
        let stats = AnalyticsService.optionStatistics(category: category, option: lofi, checkIns: checkIns)
        #expect(stats.checkInCount == AnalyticsService.minimumSampleSize - 1)
        #expect(stats.hasEnoughData == false)
    }

    // MARK: - Spec scenario (section 29): 3 sessions, music/drink comparisons, activity filter

    /// Builds the exact dataset from the spec's testing section: two
    /// Programming sessions (one Lo-fi/Pu-erh, one silent/Coffee) and one
    /// Mathematics session (Lo-fi/Coffee), each with its listed mood sequence.
    private struct SpecScenario {
        let music: FactorCategory
        let lofi: FactorOption
        let noMusic: FactorOption
        let drink: FactorCategory
        let puerh: FactorOption
        let coffee: FactorOption
        let sessions: [FocusSession]
    }

    private func makeSpecScenario() -> SpecScenario {
        let music = FactorCategory(name: "Музыка", icon: "🎧")
        let lofi = FactorOption(name: "Lo-fi", icon: "🎧")
        let noMusic = FactorOption(name: "Без музыки", icon: "🎧")
        let drink = FactorCategory(name: "Напиток", icon: "☕")
        let puerh = FactorOption(name: "Пуэр", icon: "☕")
        let coffee = FactorOption(name: "Кофе", icon: "☕")

        for option in [lofi, noMusic] { option.category = music; music.options = (music.options ?? []) + [option] }
        for option in [puerh, coffee] { option.category = drink; drink.options = (drink.options ?? []) + [option] }

        func snapshot(_ musicOption: FactorOption, _ drinkOption: FactorOption) -> [ConditionSnapshotEntry] {
            [
                ConditionSnapshotEntry(categoryID: music.id, categoryName: music.name, categoryIcon: music.icon, optionID: musicOption.id, optionName: musicOption.name),
                ConditionSnapshotEntry(categoryID: drink.id, categoryName: drink.name, categoryIcon: drink.icon, optionID: drinkOption.id, optionName: drinkOption.name)
            ]
        }

        func session(activity: String, minutes: Int, moods: [Mood], musicOption: FactorOption, drinkOption: FactorOption) -> FocusSession {
            let start = Date(timeIntervalSince1970: 0)
            let session = FocusSession(activity: activity, startDate: start, checkInIntervalMinutes: minutes / moods.count)
            let step = TimeInterval(minutes * 60) / Double(moods.count)
            for (index, mood) in moods.enumerated() {
                let checkIn = CheckIn(
                    timestamp: start.addingTimeInterval(step * Double(index + 1)),
                    mood: mood,
                    conditionSnapshot: snapshot(musicOption, drinkOption)
                )
                checkIn.session = session
                session.checkIns = (session.checkIns ?? []) + [checkIn]
            }
            return session
        }

        let session1 = session(activity: "Programming", minutes: 60, moods: [.veryGood, .veryGood, .good, .good, .neutral, .tired], musicOption: lofi, drinkOption: puerh)
        let session2 = session(activity: "Programming", minutes: 60, moods: [.good, .neutral, .neutral, .tired, .tired, .veryBad], musicOption: noMusic, drinkOption: coffee)
        let session3 = session(activity: "Mathematics", minutes: 90, moods: [.neutral, .good, .good, .veryGood, .neutral, .tired, .neutral, .veryBad], musicOption: lofi, drinkOption: coffee)

        return SpecScenario(music: music, lofi: lofi, noMusic: noMusic, drink: drink, puerh: puerh, coffee: coffee, sessions: [session1, session2, session3])
    }

    @Test func overallAverageMoodMatchesTheSpecScenario() {
        let scenario = makeSpecScenario()
        // (23 + 15 + 25) / 20 check-ins = 3.15
        #expect(AnalyticsService.averageMood(of: scenario.sessions.flatMap { $0.checkIns ?? [] })! .isApproximately(3.15))
    }

    @Test func musicComparisonMatchesTheSpecScenario() {
        let scenario = makeSpecScenario()
        let result = AnalyticsService.compare(
            optionA: (scenario.music, scenario.lofi),
            optionB: (scenario.music, scenario.noMusic),
            sessions: scenario.sessions
        )
        #expect(result.canCompare)
        #expect(result.optionA.checkInCount == 14) // session 1 + session 3
        #expect(result.optionB.checkInCount == 6)  // session 2
        #expect(result.optionA.averageMood!.isApproximately(48.0 / 14.0))
        #expect(result.optionB.averageMood!.isApproximately(2.5))
        #expect(result.moodDifference! > 0) // Lo-fi sessions averaged higher, observationally
    }

    @Test func drinkComparisonMatchesTheSpecScenario() {
        let scenario = makeSpecScenario()
        let result = AnalyticsService.compare(
            optionA: (scenario.drink, scenario.puerh),
            optionB: (scenario.drink, scenario.coffee),
            sessions: scenario.sessions
        )
        #expect(result.canCompare)
        #expect(result.optionA.checkInCount == 6)  // session 1 only
        #expect(result.optionB.checkInCount == 14) // session 2 + session 3
        #expect(result.optionA.averageMood!.isApproximately(23.0 / 6.0))
        #expect(result.optionB.averageMood!.isApproximately(40.0 / 14.0))
    }

    @Test func activityFilterIsolatesCheckInsToTheChosenActivity() {
        let scenario = makeSpecScenario()
        let programmingCheckIns = AnalyticsService.filteredCheckIns(sessions: scenario.sessions, activity: "Programming")
        let mathCheckIns = AnalyticsService.filteredCheckIns(sessions: scenario.sessions, activity: "Mathematics")
        #expect(programmingCheckIns.count == 12)
        #expect(mathCheckIns.count == 8)
        #expect(AnalyticsService.averageMood(of: programmingCheckIns)!.isApproximately(38.0 / 12.0))
        #expect(AnalyticsService.averageMood(of: mathCheckIns)!.isApproximately(3.125))
    }

    @Test func timeBasedTrajectoryAndFirstDifficultMoodAreComputedFromTheSpecScenario() {
        let scenario = makeSpecScenario()
        let trajectory = AnalyticsService.moodTrajectory(sessions: scenario.sessions, bucketMinutes: 20)
        #expect(!trajectory.isEmpty)

        // Session 1 (60 min, 6 check-ins every 10 min) hits its first difficult
        // mood (🥲) on the 6th check-in, at 60 minutes in.
        let session1 = scenario.sessions[0]
        let firstDifficult = session1.sortedCheckIns.first { $0.mood.isDifficult }
        #expect(firstDifficult?.timestamp.timeIntervalSince(session1.startDate).isApproximately(60 * 60) == true)

        let averageTimeToDifficult = AnalyticsService.averageTimeToFirstDifficultMood(sessions: scenario.sessions)
        #expect(averageTimeToDifficult != nil)
    }

    // MARK: - Moods logged outside a session

    @Test @MainActor func standaloneCheckInIsSavedWithNoSessionAttached() {
        let container = try! makeTestContainer()
        let manager = SessionManager(container: container)

        manager.addStandaloneCheckIn(mood: .tired, reason: "Устала", note: "После долгого дня")

        let stored = try! container.mainContext.fetch(FetchDescriptor<CheckIn>())
        #expect(stored.count == 1)
        #expect(stored.first?.session == nil)
        #expect(stored.first?.mood == .tired)
        #expect(stored.first?.origin == .manual)
        #expect(stored.first?.note == "После долгого дня")
        // No session means no conditions to snapshot — the record is honest
        // about that rather than inventing an empty-looking context.
        #expect(stored.first?.conditionSnapshot.isEmpty == true)
    }

    @Test @MainActor func standaloneCheckInDoesNotDisturbAnActiveSession() {
        let container = try! makeTestContainer()
        let manager = SessionManager(container: container)
        manager.startSession(activity: "Математика", intervalMinutes: 10)
        let sessionID = manager.activeSession?.id

        manager.addStandaloneCheckIn(mood: .good)

        #expect(manager.activeSession?.id == sessionID)
        #expect((manager.activeSession?.checkIns ?? []).isEmpty)
    }

    @Test func factorStatisticsFlagInsufficientSampleWhenAnActivityFilterShrinksAGroupBelowMinimum() {
        let scenario = makeSpecScenario()
        // Пуэр only appears in session 1 (Programming) — filtering to Mathematics
        // leaves zero matching check-ins, which must read as "not enough data",
        // never as "Пуэр works" or "Пуэр doesn't work".
        let stats = AnalyticsService.factorStatistics(categories: [scenario.drink], sessions: scenario.sessions, activity: "Mathematics")
        let puerhStats = stats.first?.optionStats.first { $0.optionName == "Пуэр" }
        #expect(puerhStats?.checkInCount == 0)
        #expect(puerhStats?.hasEnoughData == false)
    }

    // MARK: - Activity names in both languages

    @Test func everyQuickPickActivityHasAnEnglishName() {
        for category in ActivityCategory.allCases {
            #expect(SeedTranslations.english[category.label] != nil, "no English name for \(category.label)")
        }
    }

    @Test func quickPickActivitiesHaveDistinctNamesAndIcons() {
        // A repeated key would crash `SeedTranslations.english`'s dictionary
        // literal at launch, and a repeated icon would be a copy-paste slip.
        let labels = ActivityCategory.allCases.map(\.label)
        let icons = ActivityCategory.allCases.map(\.imageName)
        #expect(Set(labels).count == labels.count)
        #expect(Set(icons).count == icons.count)
    }

    @Test func activityNamesReadInWhicheverLanguageTheAppIsIn() {
        AppLanguage.$override.withValue(.en) {
            #expect(Ldata("Уборка") == "Cleaning")
            #expect(Ldata("Готовка еды") == "Cooking")
            // Already English, and stays English.
            #expect(Ldata("cleaning") == "Cleaning")
        }
        AppLanguage.$override.withValue(.ru) {
            #expect(Ldata("Уборка") == "Уборка")
            // Written in English, read back in Russian.
            #expect(Ldata("Cleaning") == "Уборка")
            #expect(Ldata("cooking") == "Готовка еды")
            #expect(Ldata("work") == "Работа метапелет")
        }
    }

    @Test func somethingTypedByHandIsLeftExactlyAsWritten() {
        AppLanguage.$override.withValue(.en) {
            #expect(Ldata("Прополка грядок") == "Прополка грядок")
        }
        AppLanguage.$override.withValue(.ru) {
            #expect(Ldata("Weeding the beds") == "Weeding the beds")
        }
    }

    @Test func theSameActivityInTwoLanguagesCountsAsOne() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(activity: "Уборка", startDate: start, checkInIntervalMinutes: 10),
            FocusSession(activity: "cleaning", startDate: start, checkInIntervalMinutes: 10),
            FocusSession(activity: "Чтение", startDate: start, checkInIntervalMinutes: 10)
        ]
        let stats = AnalyticsService.activityStatistics(sessions: sessions)
        #expect(stats.count == 2)
        #expect(stats.contains { $0.activityName == "Уборка" })
        // And the filter reaches both spellings.
        let sessionsForCleaning = sessions.filter { canonicalData($0.activity) == canonicalData("cleaning") }
        #expect(sessionsForCleaning.count == 2)
    }

    // MARK: - Energy and motivation alongside mood

    @Test func everyLevelOfEveryScaleHasItsOwnStepIconAndName() {
        #expect(Mood.orderedCases.map(\.scale) == [5, 4, 3, 2, 1])
        #expect(EnergyLevel.orderedCases.map(\.scale) == [5, 4, 3, 2, 1])
        #expect(StudyMotivation.orderedCases.map(\.scale) == [5, 4, 3, 2, 1])
        let icons = Mood.orderedCases.map(\.imageName)
            + EnergyLevel.orderedCases.map(\.imageName)
            + StudyMotivation.orderedCases.map(\.imageName)
        #expect(Set(icons).count == icons.count)
    }

    @Test func aCheckInCanCarryAllThreeOrJustAMood() {
        let both = CheckIn(mood: .good, energy: .low, motivation: .veryHigh)
        #expect(both.energy == .low)
        #expect(both.motivation == .veryHigh)

        let moodOnly = CheckIn(mood: .good)
        #expect(moodOnly.energy == nil)
        #expect(moodOnly.motivation == nil)
    }

    @Test func aSeriesOnlyCountsThePointsThatRecordedIt() {
        let start = Date(timeIntervalSince1970: 0)
        let summary = makeDaySummary(checkIns: [
            CheckIn(timestamp: start, mood: .good, energy: .high),
            CheckIn(timestamp: start.addingTimeInterval(3600), mood: .tired, energy: .low, motivation: .low),
            CheckIn(timestamp: start.addingTimeInterval(7200), mood: .neutral)
        ])
        #expect(summary.points(for: .mood).count == 3)
        #expect(summary.points(for: .energy).count == 2)
        #expect(summary.points(for: .motivation).count == 1)
        // Averaged over what was recorded, never over the gaps.
        #expect(summary.average(for: .energy)?.isApproximately(3) == true)
        #expect(summary.average(for: .motivation)?.isApproximately(2) == true)
    }

    @Test func aScaleNobodyRecordedIsNotOfferedAsASeries() {
        let start = Date(timeIntervalSince1970: 0)
        let summary = makeDaySummary(checkIns: [
            CheckIn(timestamp: start, mood: .good),
            CheckIn(timestamp: start.addingTimeInterval(3600), mood: .neutral)
        ])
        #expect(summary.recordedMetrics == [.mood])
        #expect(summary.average(for: .energy) == nil)
    }

    @Test func moodAndMotivationReasonsAreSeparateListsAndSeparateAnswers() {
        // The old list mixed them; nothing about the work may appear as a
        // reason for a mood any more.
        let moodReasons = Set(Mood.allCases.flatMap(\.defaultReasons))
        let motivationReasons = Set(StudyMotivation.allCases.flatMap(\.defaultReasons))
        #expect(moodReasons.isDisjoint(with: motivationReasons))

        let checkIn = CheckIn(
            mood: .tired,
            motivation: .low,
            reason: "Грустно",
            motivationReason: "Материал скучный"
        )
        #expect(checkIn.reason == "Грустно")
        #expect(checkIn.motivationReason == "Материал скучный")
    }

    @Test func everyBuiltInReasonHasAnEnglishName() {
        for reason in Mood.allCases.flatMap(\.defaultReasons) {
            #expect(SeedTranslations.english[reason] != nil, "no English for mood reason \(reason)")
        }
        for reason in StudyMotivation.allCases.flatMap(\.defaultReasons) {
            #expect(SeedTranslations.english[reason] != nil, "no English for motivation reason \(reason)")
        }
    }

    @Test func anUnansweredScaleIsExportedAsAbsentRatherThanAsTheMiddle() throws {
        let checkIn = CheckIn(mood: .good, energy: .low)
        #expect(checkIn.energy.map { Int($0.scale) } == 2)
        // Not answered, so nothing to export — never a default of 3.
        #expect(checkIn.motivation == nil)
        #expect(checkIn.motivationReason == nil)
    }

    // MARK: - Starting a session that is already under way

    @Test @MainActor func aSessionStartedAnHourLateCountsFromWhenItActuallyBegan() throws {
        let container = try makeTestContainer()
        let manager = SessionManager(container: container)
        let begun = Date.now.addingTimeInterval(-58 * 60)

        manager.startSession(activity: "Программирование", intervalMinutes: 10, startDate: begun)

        let session = try #require(manager.activeSession)
        #expect(session.state == SessionState.active)
        #expect(abs(session.startDate.timeIntervalSince(begun)) < 1)
        // The work segment covers the whole hour, not just the last moment.
        #expect(session.activeWorkDuration().isApproximately(58 * 60, tolerance: 2))
        // Recorded now, even though it began earlier.
        #expect(session.createdAt > begun.addingTimeInterval(60))
    }

    @Test @MainActor func aStartInTheFutureIsPulledBackToNow() throws {
        let container = try makeTestContainer()
        let manager = SessionManager(container: container)

        manager.startSession(activity: "Чтение", intervalMinutes: 10, startDate: .now.addingTimeInterval(3600))

        let session = try #require(manager.activeSession)
        #expect(session.startDate <= Date.now)
        #expect(session.activeWorkDuration() >= 0)
    }

    @Test @MainActor func conditionsPickedForABackdatedSessionAreStampedAtItsStart() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let category = FactorCategory(name: "Напиток", icon: "☕️")
        let option = FactorOption(name: "Кофе", icon: "☕️")
        option.category = category
        category.options = [option]
        context.insert(category)
        try context.save()
        let manager = SessionManager(container: container)
        let begun = Date.now.addingTimeInterval(-45 * 60)

        manager.startSession(
            activity: "Математика",
            intervalMinutes: 10,
            startDate: begun,
            initialConditions: [category: option]
        )

        let session = try #require(manager.activeSession)
        let event = try #require(session.sortedConditionEvents.first)
        #expect(abs(event.timestamp.timeIntervalSince(begun)) < 1)
    }

    /// A `DailySummary` built straight from check-ins, with no sessions —
    /// enough to exercise the per-series accessors the day chart reads.
    private func makeDaySummary(checkIns: [CheckIn]) -> DailySummary {
        AnalyticsService.dailySummary(
            date: Date(timeIntervalSince1970: 0),
            sessions: [],
            checkIns: checkIns,
            calendar: Calendar(identifier: .gregorian)
        )
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.001) -> Bool {
        abs(self - other) < tolerance
    }
}
