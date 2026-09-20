//
//  TodoRoutingTests.swift
//  Mood PomodoroTests
//
//  Silent delivery to ToDo List: wire format, channels, receipts, retries, privacy and the
//  pinned store location.
//

import Foundation
import SwiftData
import Testing
@testable import Mood_Pomodoro

@MainActor
struct TodoRoutingTests {
    // MARK: Stand-ins

    final class FakeChannel: SilentIntegrationChannel {
        var isAvailable = true
        var accepts = true
        private(set) var sent: [IntegrationEnvelope] = []
        func send(_ envelope: IntegrationEnvelope) async -> Bool {
            sent.append(envelope)
            return accepts
        }
    }

    final class FakeCloudStore: IntegrationCloudStore {
        var isAvailable = true
        var failing = false
        private(set) var saved: [IntegrationCloudRecord] = []
        struct Down: Error {}
        func save(_ record: IntegrationCloudRecord) async throws {
            if failing { throw Down() }
            saved.append(record)
        }
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("routing-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The app's full schema: a session is related to models a partial list would leave out,
    /// which crashes depending on which test happened to run first.
    private func makeContainer() throws -> ModelContainer {
        let schema = PersistenceController.schema
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "routing-\(UUID().uuidString)")! }

    private func finishedSession(_ manager: SessionManager, taskID: UUID?) -> FocusSession {
        let request = taskID.map { TodoFocusRequest(taskID: $0, title: "Математика", source: "calmday", requestID: nil) }
        manager.startSession(activity: "Математика", intervalMinutes: 10, startDate: .now.addingTimeInterval(-1800), sourceTask: request)
        let session = manager.activeSession!
        manager.finish()
        return session
    }

    private struct Rig {
        /// Must outlive the manager: a context does not keep its container alive.
        let container: ModelContainer
        let manager: SessionManager
        let integration: TodoIntegrationCoordinator
        let transport: TodoIntegrationRouter
        let channel: FakeChannel
    }

    private func makeRig(channel givenChannel: FakeChannel? = nil, mailbox: IntegrationMailbox? = nil) throws -> Rig {
        let channel = givenChannel ?? FakeChannel()
        let transport = TodoIntegrationRouter(channels: [channel], mailbox: mailbox)
        let container = try makeContainer()
        let manager = SessionManager(container: container)
        let file = tempDir().appendingPathComponent("outbox.json")
        let integration = TodoIntegrationCoordinator(outbox: TodoIntegrationOutbox(fileURL: file), transport: transport, defaults: defaults())
        manager.lifecycleHandler = { [weak integration] event in integration?.handle(lifecycle: event) }
        return Rig(container: container, manager: manager, integration: integration, transport: transport, channel: channel)
    }

    // MARK: Wire format

    @Test func aFinishedSessionBecomesTheContractsSessionFinished() throws {
        let taskID = UUID(), sessionID = UUID()
        let end = Date(timeIntervalSince1970: 1_790_000_000)
        let session = FocusSession(activity: "Математика", startDate: end.addingTimeInterval(-3000), checkInIntervalMinutes: 10)
        session.id = sessionID
        session.sourceTaskID = taskID
        session.endDate = end
        session.updatedAt = end
        let segment = SessionSegment(type: .work, startDate: session.startDate, endDate: end)
        segment.session = session
        session.segments = [segment]

        let event = TodoIntegrationEvent.sessionFinished(session, at: end)
        let envelope = try #require(TodoEnvelopeMapper.envelope(for: event))
        let decoded = try IntegrationCoding.decode(try IntegrationCoding.encode(envelope))

        guard case let .sessionFinished(decodedTask, decodedSession) = decoded.payload else {
            Issue.record("wrong kind"); return
        }
        #expect(decodedTask == taskID)
        #expect(decodedSession.sessionID == sessionID)
        #expect(decodedSession.activeSeconds == 3000)
        #expect(decodedSession.revision == Int64(end.timeIntervalSince1970 * 1000))
        #expect(decoded.origin.app == "moodpomodoro")
    }

    @Test func theSameOperationIsAlwaysTheSameEvent() {
        let a = TodoEnvelopeMapper.eventUUID(for: "sessionFinished:X")
        #expect(a == TodoEnvelopeMapper.eventUUID(for: "sessionFinished:X"))
        #expect(a != TodoEnvelopeMapper.eventUUID(for: "sessionFinished:Y"))
    }

    @Test func aRemovalOutranksTheFinishItRetracts() throws {
        let sessionID = UUID(), taskID = UUID()
        let end = Date(timeIntervalSince1970: 1_790_000_000)
        let session = FocusSession(activity: "x", startDate: end.addingTimeInterval(-600), checkInIntervalMinutes: 10)
        session.id = sessionID; session.sourceTaskID = taskID; session.endDate = end; session.updatedAt = end
        let finished = try #require(TodoEnvelopeMapper.envelope(for: .sessionFinished(session, at: end)))
        let removed = try #require(TodoEnvelopeMapper.envelope(for: .sessionDeleted(sessionID: sessionID, taskID: taskID, at: end.addingTimeInterval(60))))
        guard case let .sessionFinished(_, s) = finished.payload, case let .sessionRemoved(_, r) = removed.payload else {
            Issue.record("wrong kinds"); return
        }
        #expect(r > s.revision)
    }

    @Test func completionAndCreateDoneCarryTheirIds() throws {
        let taskID = UUID(), sessionID = UUID()
        let done = try #require(TodoEnvelopeMapper.envelope(for: .completionRequested(taskID: taskID, sessionID: sessionID, title: "T", at: .now)))
        #expect(done.payload == .taskCompletionRequested(taskID: taskID, sessionID: sessionID))

        let end = Date(timeIntervalSince1970: 1_790_000_000)
        let create = try #require(TodoEnvelopeMapper.envelope(for: .createDoneRequested(sessionID: sessionID, title: "  Йога  ", endedAt: end, at: end)))
        #expect(create.payload == .createDoneTaskRequested(requestID: sessionID, title: "Йога", occurredAt: end, session: nil))
    }

    @Test func eventsCarryNothingButIdsTimesAndDurations() throws {
        let session = FocusSession(activity: "Секретное название дневника", startDate: .now.addingTimeInterval(-600), checkInIntervalMinutes: 10)
        session.sourceTaskID = UUID(); session.endDate = .now
        session.note = "личная заметка"
        let envelope = try #require(TodoEnvelopeMapper.envelope(for: .sessionFinished(session, at: .now)))
        // The sender's own name ("moodpomodoro") is the one legitimate place the word appears.
        let json = String(decoding: try IntegrationCoding.encode(envelope), as: UTF8.self)
            .replacingOccurrences(of: MoodPomodoroContract.moodSource, with: "")
        for forbidden in ["личная заметка", "Секретное", "mood", "energy", "note", "sleep", "medication", "cycle", "checkIn"] {
            #expect(!json.contains(forbidden), "\(forbidden) must never be sent")
        }
    }

    @Test func theSharedFixtureFromToDoListDecodes() throws {
        let json = """
        {"createdAt":"2026-09-21T18:05:30.250Z","eventID":"5B0E7C1A-3F2D-4E8A-9C11-0A1B2C3D4E01","kind":"sessionFinished",
         "origin":{"app":"moodpomodoro"},"payload":{"session":{"activeSeconds":4800,"endedAt":"2026-09-21T18:05:30.250Z",
         "revision":1789999530250,"sessionID":"9D2C4E10-7A55-4B0C-8E3B-1F6A7C8D9E02","startedAt":"2026-09-21T16:35:12Z"},
         "taskID":"0C7B9D3E-1A24-4F60-B8D5-2E3F4A5B6C03"},"protocolVersion":1}
        """
        let envelope = try IntegrationCoding.decode(Data(json.utf8))
        guard case let .sessionFinished(_, s) = envelope.payload else { Issue.record("wrong kind"); return }
        #expect(s.activeSeconds == 4800)
    }

    // MARK: Channels

    @Test func anEventIsDeliveredOnlyWhenEveryAvailableChannelTookIt() async throws {
        let good = FakeChannel(), bad = FakeChannel()
        bad.accepts = false
        let event = TodoIntegrationEvent.completionRequested(taskID: UUID(), sessionID: UUID(), title: nil, at: .now)

        let both = TodoIntegrationRouter(channels: [good, FakeChannel()], mailbox: nil)
        #expect(await both.deliver(event, userInitiated: false) == .delivered)

        let oneFails = TodoIntegrationRouter(channels: [good, bad], mailbox: nil)
        #expect(await oneFails.deliver(event, userInitiated: false) == .unavailable)   // stays queued, retried
    }

    @Test func anUnavailableChannelIsSkippedNotFailed() async {
        let off = FakeChannel(); off.isAvailable = false
        let on = FakeChannel()
        let router = TodoIntegrationRouter(channels: [off, on], mailbox: nil)
        let event = TodoIntegrationEvent.sessionDeleted(sessionID: UUID(), taskID: UUID(), at: .now)
        #expect(await router.deliver(event, userInitiated: false) == .delivered)
        #expect(off.sent.isEmpty)
        #expect(on.sent.count == 1)
    }

    @Test func withNoChannelNothingIsDeliveredAndNothingIsOpenedBehindTheBack() async {
        let off = FakeChannel(); off.isAvailable = false
        let router = TodoIntegrationRouter(channels: [off], mailbox: nil)
        #expect(router.deliversSilently == false)
        let session = TodoIntegrationEvent.sessionDeleted(sessionID: UUID(), taskID: UUID(), at: .now)
        // Session events are never a reason to open ToDo List, even after a tap elsewhere.
        #expect(await router.deliver(session, userInitiated: true) == .unavailable)
        let completion = TodoIntegrationEvent.completionRequested(taskID: UUID(), sessionID: UUID(), title: nil, at: .now)
        #expect(await router.deliver(completion, userInitiated: false) == .unavailable)
    }

    @Test func theSharedMailboxGetsOneFilePerEventAndAResendIsHarmless() async throws {
        let mailbox = IntegrationMailbox(root: tempDir())
        let router = TodoIntegrationRouter(channels: [SharedMailboxChannel(mailbox: mailbox)], mailbox: mailbox)
        let event = TodoIntegrationEvent.completionRequested(taskID: UUID(), sessionID: UUID(), title: nil, at: .now)

        #expect(await router.deliver(event, userInitiated: true) == .delivered)
        #expect(await router.deliver(event, userInitiated: true) == .delivered)

        let files = mailbox.pendingEntries()
        #expect(files.count == 1)
        #expect(files.first?.header?.eventID == TodoEnvelopeMapper.eventUUID(for: event.id))
    }

    @Test func receiptsWrittenByToDoListAreReadBack() async throws {
        let mailbox = IntegrationMailbox(root: tempDir())
        let router = TodoIntegrationRouter(channels: [SharedMailboxChannel(mailbox: mailbox)], mailbox: mailbox)
        let event = TodoIntegrationEvent.completionRequested(taskID: UUID(), sessionID: UUID(), title: nil, at: .now)
        #expect(router.receipts(for: [event]).isEmpty)

        mailbox.writeAck(IntegrationAck(eventID: TodoEnvelopeMapper.eventUUID(for: event.id), status: .applied, processedAt: .now))
        #expect(router.receipts(for: [event])[event.id] == .applied)
    }

    @Test func theCloudRecordFollowsTheContractLayout() throws {
        let event = TodoIntegrationEvent.completionRequested(taskID: UUID(), sessionID: UUID(), title: nil, at: .now)
        let envelope = try #require(TodoEnvelopeMapper.envelope(for: event))
        let record = try #require(IntegrationCloudRecord(envelope))
        #expect(record.recordName == envelope.eventID.uuidString)
        #expect(record.recipient == "calmday")
        #expect(record.protocolVersion == 1)
        let back = try IntegrationCoding.decode(Data(record.payload.utf8))
        #expect(back.eventID == envelope.eventID)
    }

    @Test func aCloudFailureIsNotAFakeSuccess() async throws {
        let store = FakeCloudStore()
        let channel = CloudChannel(store: store)
        let envelope = try #require(TodoEnvelopeMapper.envelope(for: .sessionDeleted(sessionID: UUID(), taskID: UUID(), at: .now)))
        #expect(await channel.send(envelope))
        store.failing = true
        #expect(await channel.send(envelope) == false)
        #expect(store.saved.count == 1)
    }

    // MARK: Coordinator: automatic, explicit, retried

    @Test func aLinkedSessionReachesToDoListWithoutAnyTap() async throws {
        let rig = try makeRig()
        let taskID = UUID()
        let session = finishedSession(rig.manager, taskID: taskID)
        await rig.integration.flushQueuedSilently()

        #expect(rig.channel.sent.count == 1)
        guard case let .sessionFinished(sentTask, sentSession)? = rig.channel.sent.first?.payload else {
            Issue.record("expected sessionFinished"); return
        }
        #expect(sentTask == taskID)
        #expect(sentSession.sessionID == session.id)
        #expect(rig.integration.outbox.queued().isEmpty)
        #expect(rig.integration.outbox.awaitingReceipt().count == 1)
    }

    @Test func finishingNeverCompletesTheTaskByItself() async throws {
        let rig = try makeRig()
        _ = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.flushQueuedSilently()
        let kinds = rig.channel.sent.map(\.payload.kind)
        #expect(kinds == [.sessionFinished])
        #expect(!kinds.contains(.taskCompletionRequested))
    }

    @Test func aStandaloneSessionSendsNothingUntilTheUserAsks() async throws {
        let rig = try makeRig()
        _ = finishedSession(rig.manager, taskID: nil)
        await rig.integration.flushQueuedSilently()
        #expect(rig.channel.sent.isEmpty)
        #expect(rig.integration.outbox.events.isEmpty)
    }

    @Test func theExplicitDoneTapSendsOneRequestEvenIfPressedTwice() async throws {
        let rig = try makeRig()
        _ = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.flushQueuedSilently()

        await rig.integration.requestCompletion()
        await rig.integration.requestCompletion()

        let completions = rig.channel.sent.filter { $0.payload.kind == .taskCompletionRequested }
        #expect(completions.count == 1)
        #expect(rig.integration.prompt?.progress == .delivered)
    }

    @Test func standaloneAddToDoneIsOneRequestPerSession() async throws {
        let rig = try makeRig()
        rig.integration.prompt = TodoSessionPrompt(sessionID: UUID(), kind: .standalone(activity: "Йога"), endedAt: .now, createdAt: .now)
        await rig.integration.requestCreateDone()
        await rig.integration.requestCreateDone()
        #expect(rig.channel.sent.filter { $0.payload.kind == .createDoneTaskRequested }.count == 1)
    }

    @Test func aFailedSendStaysQueuedAndGoesOutLater() async throws {
        let channel = FakeChannel()
        channel.accepts = false
        let rig = try makeRig(channel: channel)
        _ = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.flushQueuedSilently()
        #expect(rig.integration.outbox.queued().count == 1)

        channel.accepts = true
        await rig.integration.applicationDidBecomeActive()
        #expect(rig.integration.outbox.queued().isEmpty)
        // The retry is the same event, so the receiver sees a duplicate, never a second effect.
        let ids = Set(channel.sent.map(\.eventID))
        #expect(ids.count == 1)
    }

    @Test func deletingALinkedSessionAfterDeliveryTellsToDoList() async throws {
        let rig = try makeRig()
        let session = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.flushQueuedSilently()
        rig.manager.delete(session)
        await rig.integration.flushQueuedSilently()
        #expect(rig.channel.sent.map(\.payload.kind).contains(.sessionRemoved))
    }

    @Test func receiptsEndOrParkAnEvent() async throws {
        let mailbox = IntegrationMailbox(root: tempDir())
        let rig = try makeRig(channel: FakeChannel(), mailbox: mailbox)
        _ = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.flushQueuedSilently()
        let event = try #require(rig.integration.outbox.events.first)
        let uuid = TodoEnvelopeMapper.eventUUID(for: event.id)

        mailbox.writeAck(IntegrationAck(eventID: uuid, status: .rejected, processedAt: .now))
        rig.integration.collectReceipts()
        #expect(rig.integration.outbox.event(withID: event.id)?.delivery == .rejected)
        #expect(rig.integration.outbox.queued().isEmpty)   // never retried

        mailbox.writeAck(IntegrationAck(eventID: uuid, status: .applied, processedAt: .now))
        // A rejected event is not awaiting a receipt any more; nothing more is read for it.
        rig.integration.collectReceipts()
        #expect(rig.integration.outbox.event(withID: event.id)?.delivery == .rejected)
    }

    @Test func anAppliedReceiptForgetsTheEvent() async throws {
        let mailbox = IntegrationMailbox(root: tempDir())
        let rig = try makeRig(channel: FakeChannel(), mailbox: mailbox)
        _ = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.flushQueuedSilently()
        let event = try #require(rig.integration.outbox.events.first)
        mailbox.writeAck(IntegrationAck(eventID: TodoEnvelopeMapper.eventUUID(for: event.id), status: .applied, processedAt: .now))
        rig.integration.collectReceipts()
        #expect(rig.integration.outbox.events.isEmpty)
    }

    // MARK: Independence and data safety

    @Test func withoutAnyChannelTheAppJustKeepsWorking() async throws {
        let off = FakeChannel(); off.isAvailable = false
        let rig = try makeRig(channel: off)
        let session = finishedSession(rig.manager, taskID: UUID())
        await rig.integration.applicationDidBecomeActive()
        #expect(session.state == .completed)                     // the session is saved regardless
        #expect(rig.integration.outbox.queued().count == 1)      // and waits, silently
    }

    @Test func theDiaryStoreNeverMovesIntoTheAppGroupContainer() {
        for cloud in [true, false] {
            let path = PersistenceController.configuration(cloudKit: cloud).url.path
            #expect(!path.contains("/AppGroup/"), "the diary must stay in the app's own container: \(path)")
        }
    }
}
