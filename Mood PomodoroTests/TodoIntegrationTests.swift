import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

/// Mood Pomodoro's side of the ToDo List integration. The other app is never
/// present here: a stand-in transport records what it was asked to deliver.
@MainActor
struct TodoIntegrationTests {
    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
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

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-outbox-\(UUID().uuidString).json")
    }

    private func suiteDefaults() -> UserDefaults {
        UserDefaults(suiteName: "todo-tests-\(UUID().uuidString)")!
    }

    @MainActor
    final class StandInTransport: TodoIntegrationTransport {
        var isTodoAppInstalled = true
        var deliversSilently = false
        var supported: Set<TodoIntegrationEventType> = [.taskCompletionRequested]
        var result: TodoDeliveryResult = .handedOff
        private(set) var delivered: [TodoIntegrationEvent] = []
        /// For each delivery: was it a tap (`true`) or a background flush (`false`)?
        private(set) var userInitiated: [Bool] = []
        var receiptStatuses: [String: IntegrationAckStatus] = [:]

        func canDeliver(_ type: TodoIntegrationEventType) -> Bool { supported.contains(type) }
        func deliver(_ event: TodoIntegrationEvent, userInitiated: Bool) async -> TodoDeliveryResult {
            delivered.append(event)
            self.userInitiated.append(userInitiated)
            return result
        }
        func receipts(for events: [TodoIntegrationEvent]) -> [String: IntegrationAckStatus] {
            let ids = Set(events.map(\.id))
            return receiptStatuses.filter { ids.contains($0.key) }
        }
    }

    private struct Rig {
        let container: ModelContainer
        let manager: SessionManager
        let integration: TodoIntegrationCoordinator
        let transport: StandInTransport
        let outboxFile: URL
    }

    private func makeRig(outboxFile: URL? = nil, transport: StandInTransport? = nil) throws -> Rig {
        let transport = transport ?? StandInTransport()
        let container = try makeContainer()
        let file = outboxFile ?? tempFile()
        let manager = SessionManager(container: container)
        let integration = TodoIntegrationCoordinator(
            outbox: TodoIntegrationOutbox(fileURL: file),
            transport: transport,
            defaults: suiteDefaults()
        )
        manager.lifecycleHandler = { [weak integration] event in integration?.handle(lifecycle: event) }
        return Rig(container: container, manager: manager, integration: integration, transport: transport, outboxFile: file)
    }

    private func focusURL(
        taskID: UUID = UUID(),
        title: String = "Домашнее задание по математике",
        source: String? = "calmday",
        requestID: String? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = "moodpomodoro"
        components.host = "focus"
        var items = [URLQueryItem(name: "taskId", value: taskID.uuidString), URLQueryItem(name: "title", value: title)]
        if let source { items.append(URLQueryItem(name: "source", value: source)) }
        if let requestID { items.append(URLQueryItem(name: "requestId", value: requestID)) }
        components.queryItems = items
        return components.url!
    }

    private func request(taskID: UUID = UUID(), title: String = "Задача", requestID: String? = nil) -> TodoFocusRequest {
        TodoFocusRequest(taskID: taskID, title: title, source: "calmday", requestID: requestID)
    }

    // MARK: - 1–2. Incoming link

    @Test func aValidLinkIsReadInFull() throws {
        let id = UUID()
        let result = TodoFocusRequest.parse(focusURL(taskID: id, title: "Домашнее задание по математике"))
        let parsed = try result.get()
        #expect(parsed.taskID == id)
        #expect(parsed.title == "Домашнее задание по математике")
        #expect(parsed.source == "calmday")
    }

    @Test func theLinkToDoListActuallySendsIsAccepted() throws {
        // Exactly what ToDo List's MoodPomodoroBridge builds, no requestId.
        let url = URL(string: "moodpomodoro://focus?taskId=\(UUID().uuidString)&title=Read%20chapter&source=calmday")!
        #expect(try TodoFocusRequest.parse(url).get().title == "Read chapter")
    }

    @Test func brokenLinksAreRejectedForTheRightReason() {
        let id = UUID().uuidString
        func failure(_ string: String) -> TodoFocusRequest.Failure? {
            guard case .failure(let error) = TodoFocusRequest.parse(URL(string: string)!) else { return nil }
            return error
        }
        #expect(failure("https://example.com/focus?taskId=\(id)&title=x") == .wrongScheme)
        #expect(failure("moodpomodoro://settings?taskId=\(id)&title=x") == .wrongAction)
        #expect(failure("moodpomodoro://focus?title=x") == .missingTaskID)
        #expect(failure("moodpomodoro://focus?taskId=not-a-uuid&title=x") == .invalidTaskID)
        #expect(failure("moodpomodoro://focus?taskId=\(id)") == .missingTitle)
        #expect(failure("moodpomodoro://focus?taskId=\(id)&title=%20%20") == .missingTitle)
        #expect(failure("moodpomodoro://focus?taskId=\(id)&title=x&source=other") == .unknownSource)
    }

    @Test func aTitleFromOutsideIsCleanedAndBounded() throws {
        let long = String(repeating: "я", count: 500)
        let parsed = try TodoFocusRequest.parse(focusURL(title: "  Line\none\t two  ")).get()
        #expect(parsed.title == "Line one two")
        #expect(try TodoFocusRequest.parse(focusURL(title: long)).get().title.count == TodoIntegrationContract.maxTitleLength)
    }

    @Test func aBrokenLinkChangesNothing() throws {
        let rig = try makeRig()
        let handled = rig.integration.handle(url: URL(string: "moodpomodoro://focus?taskId=oops&title=x")!, activeSession: nil)
        #expect(handled == false)
        #expect(rig.integration.pendingFocus == nil)
        #expect(rig.manager.activeSession == nil)
    }

    // MARK: - 3–6. Starting, re-opening, running session, standalone

    @Test func aLinkPreparesTheStartScreenAndNeverStartsASession() throws {
        let rig = try makeRig()
        let id = UUID()
        #expect(rig.integration.handle(url: focusURL(taskID: id), activeSession: rig.manager.activeSession))
        #expect(rig.integration.pendingFocus?.taskID == id)
        #expect(rig.manager.activeSession == nil)
    }

    @Test func aSessionStartedFromATaskKeepsTheLinkAndTheTitle() throws {
        let rig = try makeRig()
        let req = request(title: "Реферат")
        rig.manager.startSession(activity: "Реферат", intervalMinutes: 10, type: .study, sourceTask: req)
        let session = try #require(rig.manager.activeSession)
        #expect(session.sourceTaskID == req.taskID)
        #expect(session.sourceTaskTitle == "Реферат")
        #expect(session.sourceApp == "calmday")
        #expect(session.isLinkedToTask)
    }

    @Test func openingTheSameTaskTwiceNeverStartsTwoSessions() throws {
        let rig = try makeRig()
        let id = UUID()
        rig.manager.startSession(activity: "A", intervalMinutes: 10, sourceTask: request(taskID: id))
        let first = try #require(rig.manager.activeSession)
        // The same link arrives again while its session runs.
        rig.integration.handle(url: focusURL(taskID: id), activeSession: rig.manager.activeSession)
        rig.manager.startSession(activity: "A", intervalMinutes: 10, sourceTask: request(taskID: id))
        #expect(rig.integration.conflict == nil)
        #expect(rig.integration.pendingFocus == nil)
        #expect(rig.manager.activeSession?.id == first.id)
        let all = try rig.container.mainContext.fetch(FetchDescriptor<FocusSession>())
        #expect(all.count == 1)
    }

    @Test func aDifferentTaskDuringARunningSessionWaitsAndTouchesNothing() throws {
        let rig = try makeRig()
        rig.manager.startSession(activity: "Чтение", intervalMinutes: 10)
        let running = try #require(rig.manager.activeSession)
        let other = UUID()
        #expect(rig.integration.handle(url: focusURL(taskID: other, title: "Задача"), activeSession: running))
        #expect(rig.integration.pendingFocus?.taskID == other)
        #expect(rig.integration.conflict == .init(runningActivity: "Чтение", requestedTitle: "Задача"))
        #expect(rig.manager.activeSession?.id == running.id)
        #expect(running.state == .active)
        #expect(running.endDate == nil)
        // The user can set it aside.
        rig.integration.dismissFocus()
        #expect(rig.integration.pendingFocus == nil)
        #expect(rig.integration.conflict == nil)
    }

    @Test func aRedeliveredRequestIsNotShownAgainOnceUsed() throws {
        let rig = try makeRig()
        let req = request(requestID: "r-1")
        rig.integration.handle(url: focusURL(taskID: req.taskID, requestID: "r-1"), activeSession: nil)
        #expect(rig.integration.pendingFocus?.requestID == "r-1")
        rig.integration.focusDidStart(req)
        #expect(rig.integration.pendingFocus == nil)
        rig.integration.handle(url: focusURL(taskID: req.taskID, requestID: "r-1"), activeSession: nil)
        #expect(rig.integration.pendingFocus == nil)
    }

    @Test func aStandaloneSessionHasNoTaskAndSendsNothing() throws {
        let rig = try makeRig()
        rig.manager.startSession(activity: "Рисование", intervalMinutes: 10, type: .rest)
        let session = try #require(rig.manager.activeSession)
        #expect(session.sourceTaskID == nil)
        #expect(session.sourceTaskTitle == nil)
        rig.manager.finish()
        #expect(rig.integration.prompt == nil)
        #expect(rig.integration.outbox.events.isEmpty)
    }

    // MARK: - 7–10. Finishing

    /// Three hours on the clock: an hour of work, an hour of break, an hour
    /// of work still open. Only the two working hours are activity.
    private func startSessionWithABreak(_ rig: Rig, taskID: UUID?) -> FocusSession {
        let start = Date.now.addingTimeInterval(-3 * 3600)
        let session = FocusSession(activity: "Матан", startDate: start, checkInIntervalMinutes: 10)
        if let taskID {
            session.sourceTaskID = taskID
            session.sourceTaskTitle = "Матан"
            session.sourceApp = "calmday"
        }
        session.sessionType = .study
        rig.container.mainContext.insert(session)
        let first = SessionSegment(type: .work, startDate: start, endDate: start.addingTimeInterval(3600))
        let pause = SessionSegment(type: .pause, startDate: start.addingTimeInterval(3600), endDate: start.addingTimeInterval(7200))
        let second = SessionSegment(type: .work, startDate: start.addingTimeInterval(7200))
        for segment in [first, pause, second] { segment.session = session }
        session.segments = [first, pause, second]
        try? rig.container.mainContext.save()
        rig.manager.refresh()
        return session
    }

    @Test func finishingALinkedSessionReportsActiveTimeNotWallClockTime() throws {
        let rig = try makeRig()
        let taskID = UUID()
        let session = startSessionWithABreak(rig, taskID: taskID)
        rig.manager.finish()

        let event = try #require(rig.integration.outbox.event(withID: "sessionFinished:\(session.id.uuidString)"))
        #expect(event.taskID == taskID)
        #expect(event.sessionID == session.id)
        let active = try #require(event.activeDurationSeconds)
        #expect(abs(active - 7200) < 5)
        #expect(session.totalDuration() > 3 * 3600 - 5)   // wall clock is longer
        #expect(active < session.totalDuration() - 3000)
        #expect(event.startedAt == session.startDate)
        #expect(event.endedAt == session.endDate)
        #expect(session.state == .completed)
        #expect(session.currentSegment == nil)
    }

    @Test func finishingNeverCompletesTheTask() throws {
        let rig = try makeRig()
        _ = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.finish()
        #expect(rig.integration.outbox.events.contains { $0.type == .taskCompletionRequested } == false)
        #expect(rig.transport.delivered.isEmpty)
        // A prompt is offered, and answering nothing changes nothing.
        guard case .linkedTask = rig.integration.prompt?.kind else { Issue.record("no linked prompt"); return }
        rig.integration.dismissPrompt()
        #expect(rig.integration.outbox.events.contains { $0.type == .taskCompletionRequested } == false)
    }

    @Test func aTypedInEntryIsNotOfferedAnything() throws {
        let rig = try makeRig()
        let manual = FocusSession(activity: "Вчера", startDate: .now.addingTimeInterval(-7200), checkInIntervalMinutes: 10)
        manual.origin = .manual
        manual.state = .completed
        manual.endDate = .now
        manual.sourceTaskID = UUID()
        rig.integration.handle(lifecycle: .finished(manual))
        #expect(rig.integration.prompt == nil)
        #expect(rig.integration.outbox.events.isEmpty)
    }

    // MARK: - 11–12. "Готово"

    @Test func doneAsksTheOtherAppOnceAndRepeatsAreTheSameOperation() async throws {
        let rig = try makeRig()
        let taskID = UUID()
        let session = startSessionWithABreak(rig, taskID: taskID)
        rig.manager.finish()

        await rig.integration.requestCompletion()
        await rig.integration.requestCompletion()
        await rig.integration.requestCompletion()

        let completions = rig.integration.outbox.events.filter { $0.type == .taskCompletionRequested }
        #expect(completions.count == 1)
        #expect(completions[0].id == "taskCompletionRequested:\(taskID.uuidString):\(session.id.uuidString)")
        #expect(completions[0].delivery == .handedOff)
        #expect(rig.transport.delivered.count == 1)
        #expect(rig.integration.prompt?.progress == .handedOff)
    }

    @Test func doneWithoutTheOtherAppIsSavedAndNotClaimedDelivered() async throws {
        let transport = StandInTransport()
        transport.isTodoAppInstalled = false
        transport.result = .unavailable
        let rig = try makeRig(transport: transport)
        _ = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.finish()

        await rig.integration.requestCompletion()
        #expect(rig.integration.prompt?.progress == .queued)
        let saved = rig.integration.outbox.events.first { $0.type == .taskCompletionRequested }
        #expect(saved?.delivery == .queued)

        // The other app appears; the same request goes through, still one.
        transport.result = .handedOff
        await rig.integration.requestCompletion()
        #expect(rig.integration.outbox.events.filter { $0.type == .taskCompletionRequested }.count == 1)
        #expect(rig.integration.prompt?.progress == .handedOff)
    }

    @Test func theSessionIsSavedWhetherOrNotTheOtherAppExists() throws {
        let transport = StandInTransport()
        transport.isTodoAppInstalled = false
        let rig = try makeRig(transport: transport)
        let session = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.finish()
        #expect(session.state == .completed)
        #expect(try rig.container.mainContext.fetch(FetchDescriptor<FocusSession>()).count == 1)
    }

    // MARK: - 13–14. "Добавить в сделанное?"

    @Test func addToDoneIsOnlyOfferedWhenTheOtherAppCanTakeIt() throws {
        let rig = try makeRig()   // today's contract: it cannot
        rig.manager.startSession(activity: "Прогулка", intervalMinutes: 10, type: .rest)
        rig.manager.finish()
        #expect(rig.integration.prompt == nil)
    }

    @Test func addToDoneCreatesOneRequestOnlyWhenAsked() async throws {
        let transport = StandInTransport()
        transport.supported = [.taskCompletionRequested, .createDoneTaskRequested]
        let rig = try makeRig(transport: transport)

        // Two sessions finish; nothing is created by itself.
        rig.manager.startSession(activity: "Рисование", intervalMinutes: 10, type: .rest)
        rig.manager.finish()
        #expect(rig.integration.prompt?.kind == .standalone(activity: "Рисование"))
        #expect(rig.integration.outbox.events.isEmpty)
        rig.integration.dismissPrompt()
        rig.manager.startSession(activity: "Чтение", intervalMinutes: 10, type: .rest)
        rig.manager.finish()
        #expect(rig.integration.outbox.events.isEmpty)

        // Asked once, twice: one request.
        await rig.integration.requestCreateDone()
        await rig.integration.requestCreateDone()
        let created = rig.integration.outbox.events.filter { $0.type == .createDoneTaskRequested }
        #expect(created.count == 1)
        let request = try #require(created.first)
        #expect(request.title == "Чтение")
        #expect(request.sessionID != nil)
        #expect(rig.transport.delivered.count == 1)
    }

    @Test func createDoneLinkCarriesTheContractEnvelopeAndIsStable() throws {
        let sessionID = UUID()
        let endedAt = Date(timeIntervalSince1970: 1_790_000_400)
        let event = TodoIntegrationEvent.createDoneRequested(sessionID: sessionID, title: "Йога & растяжка", endedAt: endedAt, at: endedAt)

        let url = try #require(URLSchemeTodoTransport.createDoneURL(for: event))
        #expect(url.scheme == "calmday")
        #expect(url.host == "integration")

        let data = try #require(IntegrationEventURL.envelopeData(from: url))
        let envelope = try IntegrationCoding.decode(data)
        #expect(envelope.origin.app == "moodpomodoro")
        guard case .createDoneTaskRequested(let requestID, let title, let occurredAt, let session) = envelope.payload else {
            Issue.record("wrong payload")
            return
        }
        #expect(requestID == sessionID)
        #expect(title == "Йога & растяжка")
        #expect(occurredAt == endedAt)
        #expect(session == nil)

        // Pressing again re-sends the same event.
        let again = try #require(URLSchemeTodoTransport.createDoneURL(for: event))
        #expect(again == url)
    }

    @Test func aDeclinedOfferLeavesTheSessionOnlyHere() throws {
        let transport = StandInTransport()
        transport.supported = [.createDoneTaskRequested]
        let rig = try makeRig(transport: transport)
        rig.manager.startSession(activity: "Лего", intervalMinutes: 10, type: .rest)
        rig.manager.finish()
        rig.integration.dismissPrompt()
        #expect(rig.integration.prompt == nil)
        #expect(rig.integration.outbox.events.isEmpty)
        #expect(try rig.container.mainContext.fetch(FetchDescriptor<FocusSession>()).count == 1)
    }

    // MARK: - 16–17. Offline, restart

    @Test func theQueueSurvivesARestart() async throws {
        let file = tempFile()
        let taskID = UUID()
        do {
            let transport = StandInTransport()
            transport.result = .unavailable
            let rig = try makeRig(outboxFile: file, transport: transport)
            let session = startSessionWithABreak(rig, taskID: taskID)
            rig.manager.finish()
            await rig.integration.requestCompletion()
            #expect(rig.integration.outbox.events.count == 2)   // finished + completion request
            _ = session
        }
        // A fresh process reads the same file.
        let reopened = TodoIntegrationOutbox(fileURL: file)
        #expect(reopened.events.count == 2)
        #expect(reopened.queued().count == 2)
        #expect(reopened.events.contains { $0.type == .taskCompletionRequested && $0.taskID == taskID })
    }

    @Test func aSilentChannelFlushesWhatWaitedOnceTheAppIsActive() async throws {
        let file = tempFile()
        let seed = TodoIntegrationOutbox(fileURL: file)
        seed.enqueue(.completionRequested(taskID: UUID(), sessionID: UUID(), title: "T", at: .now))

        let transport = StandInTransport()
        transport.deliversSilently = true
        transport.result = .delivered
        let integration = TodoIntegrationCoordinator(
            outbox: TodoIntegrationOutbox(fileURL: file),
            transport: transport,
            defaults: suiteDefaults()
        )
        await integration.applicationDidBecomeActive()
        #expect(transport.delivered.count == 1)
        #expect(integration.outbox.queued().isEmpty)
        await integration.applicationDidBecomeActive()
        #expect(transport.delivered.count == 1)   // not sent again
    }

    @Test func aChannelThatSwitchesAppsIsNeverUsedBehindTheUsersBack() async throws {
        let file = tempFile()
        let seed = TodoIntegrationOutbox(fileURL: file)
        seed.enqueue(.completionRequested(taskID: UUID(), sessionID: UUID(), title: "T", at: .now))
        let transport = StandInTransport()   // deliversSilently == false
        let integration = TodoIntegrationCoordinator(outbox: TodoIntegrationOutbox(fileURL: file), transport: transport, defaults: suiteDefaults())
        await integration.applicationDidBecomeActive()
        #expect(transport.delivered.isEmpty)
    }

    @Test func anUnreadableQueueFileIsSetAsideNotLost() throws {
        let file = tempFile()
        try Data("not json".utf8).write(to: file)
        let outbox = TodoIntegrationOutbox(fileURL: file)
        #expect(outbox.events.isEmpty)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.hasPrefix("todo-outbox.unreadable-") })
    }

    // MARK: - 18. Corrections and deletion

    @Test func deletingALinkedSessionBeforeItWasDeliveredLeavesNothingToTell() throws {
        let rig = try makeRig()
        let session = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.finish()
        #expect(rig.integration.outbox.events.count == 1)
        rig.manager.delete(session)
        #expect(rig.integration.outbox.events.isEmpty)
    }

    @Test func deletingADeliveredSessionLeavesATombstone() throws {
        let rig = try makeRig()
        let taskID = UUID()
        let session = startSessionWithABreak(rig, taskID: taskID)
        let sessionID = session.id
        rig.manager.finish()
        rig.integration.outbox.markHandedOff("sessionFinished:\(sessionID.uuidString)")
        rig.manager.delete(session)
        let events = rig.integration.outbox.events
        #expect(events.count == 1)
        #expect(events[0].type == .sessionDeleted)
        #expect(events[0].sessionID == sessionID)
        #expect(events[0].taskID == taskID)
    }

    @Test func aCorrectionReplacesTheSessionInsteadOfAddingAnother() throws {
        let rig = try makeRig()
        let session = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.finish()
        session.touch(at: .now.addingTimeInterval(60))
        rig.integration.sessionDidUpdate(session)
        let forSession = rig.integration.outbox.events.filter { $0.sessionID == session.id }
        #expect(forSession.count == 1)
        #expect(forSession[0].type == .sessionUpdated)
    }

    @Test func deletingTheTaskOverThereNeverDeletesTheSessionHere() throws {
        // Nothing in this app reacts to a task disappearing: the link is a
        // plain id and a title, with no relationship to cascade through.
        let rig = try makeRig()
        let session = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.finish()
        #expect(session.sourceTaskTitle == "Матан")
        #expect(try rig.container.mainContext.fetch(FetchDescriptor<FocusSession>()).count == 1)
    }

    @Test func cancellingARunningLinkedSessionTellsNobody() throws {
        let rig = try makeRig()
        rig.manager.startSession(activity: "A", intervalMinutes: 10, sourceTask: request())
        rig.manager.cancel()
        #expect(rig.integration.outbox.events.isEmpty)
        #expect(rig.integration.prompt == nil)
    }

    // MARK: - 19. Old data

    @Test func sessionsFromBeforeTheLinkStayValid() throws {
        let rig = try makeRig()
        let old = FocusSession(activity: "Старое", startDate: .now.addingTimeInterval(-86400), checkInIntervalMinutes: 10)
        old.state = .completed
        old.endDate = .now.addingTimeInterval(-82800)
        rig.container.mainContext.insert(old)
        try rig.container.mainContext.save()
        let fetched = try #require(try rig.container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        #expect(fetched.sourceTaskID == nil)
        #expect(fetched.sourceTaskTitle == nil)
        #expect(fetched.sourceApp == nil)
        #expect(fetched.isLinkedToTask == false)
    }

    @Test func theLastSessionOfATaskSuppliesItsSavedAnswers() throws {
        let rig = try makeRig()
        let taskID = UUID()
        rig.manager.startSession(activity: "T", intervalMinutes: 20, type: .obligatoryWork, sourceTask: request(taskID: taskID))
        rig.manager.finish()
        let last = try #require(rig.manager.lastSession(forTask: taskID))
        #expect(last.checkInIntervalMinutes == 20)
        #expect(last.sessionType == .obligatoryWork)
        #expect(rig.manager.lastSession(forTask: UUID()) == nil)
    }

    @Test func aTypeIsNeverInventedFromTheTitle() throws {
        let rig = try makeRig()
        rig.manager.startSession(activity: "Программирование", intervalMinutes: 10, sourceTask: request(title: "Программирование"))
        #expect(rig.manager.activeSession?.sessionType == nil)
    }

    // MARK: - 20. Analytics and export

    @Test func severalSessionsOfOneTaskAreGroupedAndStandaloneOnesAreNot() throws {
        let rig = try makeRig()
        let taskID = UUID()
        func finished(_ hours: Double, linked: Bool) -> FocusSession {
            let start = Date.now.addingTimeInterval(-hours * 3600)
            let session = FocusSession(activity: "A", startDate: start, checkInIntervalMinutes: 10)
            if linked { session.sourceTaskID = taskID; session.sourceTaskTitle = "Задача" }
            session.state = .completed
            session.endDate = .now
            let segment = SessionSegment(type: .work, startDate: start, endDate: .now)
            segment.session = session
            session.segments = [segment]
            return session
        }
        let sessions = [finished(1, linked: true), finished(2, linked: true), finished(1, linked: false)]
        let stats = AnalyticsService.linkedTaskStatistics(sessions: sessions)
        #expect(stats.count == 1)
        #expect(stats[0].sessionCount == 2)
        #expect(abs(stats[0].activeDuration - 3 * 3600) < 5)
        #expect(stats[0].title == "Задача")
        // The existing analytics still see every session.
        #expect(AnalyticsService.overview(sessions: sessions).sessionCount == 3)
    }

    @Test func theExportCarriesTheLinkOnlyWhereThereIsOne() throws {
        let start = Date(timeIntervalSince1970: 1_726_000_000)
        func session(linked: Bool) -> FocusSession {
            let s = FocusSession(activity: "A", startDate: start, checkInIntervalMinutes: 10)
            s.state = .completed
            s.endDate = start.addingTimeInterval(3600)
            let segment = SessionSegment(type: .work, startDate: start, endDate: start.addingTimeInterval(3600))
            segment.session = s
            s.segments = [segment]
            if linked {
                s.sourceTaskID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")
                s.sourceTaskTitle = "Задача"
                s.sourceApp = "calmday"
            }
            return s
        }
        let options = ExportOptions(
            start: start.addingTimeInterval(-86400), end: start.addingTimeInterval(86400),
            language: .en, format: .json, includeNotes: true, includeHealth: false
        )
        let document = DiaryExporter.assemble(ExportInput(sessions: [session(linked: true), session(linked: false)]), options: options)
        let linked = document.sessions.filter { $0.integration != nil }
        #expect(linked.count == 1)
        #expect(linked[0].integration?.sourceTaskId == "11111111-1111-1111-1111-111111111111")
        #expect(linked[0].integration?.sourceApp == "calmday")
        #expect(linked[0].activeDurationSeconds == 3600)

        let json = DiaryExporter.render(document, options: options)
        #expect(json.contains("\"integration\""))
        // A document written before the field existed still reads.
        let plain = DiaryExporter.render(DiaryExporter.assemble(ExportInput(sessions: [session(linked: false)]), options: options), options: options)
        #expect(plain.contains("\"integration\"") == false)
        #expect(document.schemaVersion == DiaryExporter.schemaVersion)
    }

    // MARK: - Privacy of the channel

    @Test func theQueueCarriesNothingFromTheDiary() throws {
        let rig = try makeRig()
        let session = startSessionWithABreak(rig, taskID: UUID())
        rig.manager.addCheckIn(mood: .veryBad, reason: "очень плохо", note: "секрет", to: session)
        rig.manager.finish()
        let data = try Data(contentsOf: rig.outboxFile)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("секрет") == false)
        #expect(text.contains("очень плохо") == false)
        #expect(text.lowercased().contains("mood") == false)
        #expect(text.lowercased().contains("sleep") == false)
    }
}
