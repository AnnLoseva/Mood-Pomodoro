//
//  TodoIntegrationTransport.swift
//  Mood Pomodoro
//

import CloudKit
import CryptoKit
import Foundation
import UIKit

enum TodoDeliveryResult: Equatable {
    /// A channel that needs no app switch took the event (shared mailbox and/or iCloud).
    /// This means "left this app safely" — not "ToDo List applied it".
    case delivered
    /// The other app was opened with the event. There is no receipt on this path.
    case handedOff
    /// Nothing can take it right now. The event stays queued and is tried again later.
    case unavailable
}

/// How an event reaches ToDo List. Behind a protocol so the queue, the card and the tests do not
/// care which channel is in use.
@MainActor
protocol TodoIntegrationTransport {
    /// Whether ToDo List is on this device at all — decides if the app offers anything about it.
    var isTodoAppInstalled: Bool { get }
    /// True when at least one channel delivers without switching apps. Only such channels may be
    /// used from a background flush.
    var deliversSilently: Bool { get }
    func canDeliver(_ type: TodoIntegrationEventType) -> Bool
    /// `userInitiated` allows the one channel that opens the other app (a tap on an explicit
    /// "Готово" / "Добавить в сделанное"); without it nothing ever leaves the app.
    func deliver(_ event: TodoIntegrationEvent, userInitiated: Bool) async -> TodoDeliveryResult
    /// Receipts ToDo List left for these events (same-device mailbox only).
    func receipts(for events: [TodoIntegrationEvent]) -> [String: IntegrationAckStatus]
}

// MARK: - Event → contract envelope

/// Turns this app's queued event into the shared contract's envelope. The only place that knows
/// the wire format; nothing but ids, times and durations goes through it.
enum TodoEnvelopeMapper {
    /// The contract wants UUID event ids; the outbox's ids are readable strings derived from the
    /// operation. The UUID is derived from the string too, so the same operation is always the
    /// same event — a re-send is a duplicate to ToDo List, never a second effect.
    static func eventUUID(for id: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data(id.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func revision(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

    static func envelope(for event: TodoIntegrationEvent) -> IntegrationEnvelope? {
        let payload: IntegrationPayload
        switch event.type {
        case .sessionFinished, .sessionUpdated:
            guard let taskID = event.taskID, let sessionID = event.sessionID, let endedAt = event.endedAt else { return nil }
            let seconds = Int((event.activeDurationSeconds ?? 0).rounded())
            payload = .sessionFinished(taskID: taskID, session: IntegrationSession(
                sessionID: sessionID,
                revision: revision(event.revision ?? event.createdAt),
                startedAt: event.startedAt,
                endedAt: endedAt,
                activeSeconds: min(max(seconds, 0), MoodPomodoroContract.maxActiveSeconds)
            ))
        case .sessionDeleted:
            guard let sessionID = event.sessionID else { return nil }
            // Later than any revision sent for this session: the removal must win over them.
            payload = .sessionRemoved(sessionID: sessionID, revision: revision(event.revision ?? event.createdAt))
        case .taskCompletionRequested:
            guard let taskID = event.taskID else { return nil }
            payload = .taskCompletionRequested(taskID: taskID, sessionID: event.sessionID)
        case .createDoneTaskRequested:
            guard let sessionID = event.sessionID,
                  let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let occurredAt = event.endedAt else { return nil }
            // One request per session: pressing again re-sends the same request.
            payload = .createDoneTaskRequested(
                requestID: sessionID,
                title: String(title.prefix(MoodPomodoroContract.maxTitleLength)),
                occurredAt: occurredAt,
                session: nil
            )
        }
        return IntegrationEnvelope(
            eventID: eventUUID(for: event.id),
            createdAt: event.createdAt,
            origin: IntegrationOrigin(app: MoodPomodoroContract.moodSource),
            payload: payload
        )
    }

    /// The kinds a user chose with a tap. Only these may open ToDo List.
    static func isExplicitUserAction(_ type: TodoIntegrationEventType) -> Bool {
        type == .taskCompletionRequested || type == .createDoneTaskRequested
    }
}

// MARK: - Silent channels

/// A channel that carries an envelope without switching apps.
@MainActor
protocol SilentIntegrationChannel {
    var isAvailable: Bool { get }
    /// True once the envelope is safely in the channel. Sending the same envelope again is harmless.
    func send(_ envelope: IntegrationEnvelope) async -> Bool
}

/// Same device: a file per event in the App Group container ToDo List also reads.
/// Unavailable (nil container) until the capability is provisioned — then nothing is attempted.
@MainActor
struct SharedMailboxChannel: SilentIntegrationChannel {
    let mailbox: IntegrationMailbox?

    init(mailbox: IntegrationMailbox? = SharedMailboxChannel.groupMailbox()) {
        self.mailbox = mailbox
    }

    nonisolated static func groupMailbox() -> IntegrationMailbox? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: MoodPomodoroContract.appGroupID)
            .map(IntegrationMailbox.inGroupContainer)
    }

    var isAvailable: Bool { mailbox != nil }

    func send(_ envelope: IntegrationEnvelope) async -> Bool {
        guard let mailbox else { return false }
        do {
            _ = try mailbox.enqueue(envelope)   // false = already queued: as good as sent
            return true
        } catch {
            return false
        }
    }
}

/// The record a CloudKit event becomes. Kept as plain values so the layout is testable without iCloud.
struct IntegrationCloudRecord: Equatable {
    var recordName: String
    var recipient: String
    var payload: String
    var createdAt: Date
    var protocolVersion: Int64

    init?(_ envelope: IntegrationEnvelope) {
        guard let data = try? IntegrationCoding.encode(envelope),
              let json = String(data: data, encoding: .utf8) else { return nil }
        recordName = envelope.eventID.uuidString
        recipient = MoodPomodoroContract.cloudRecipientTodo
        payload = json
        createdAt = envelope.createdAt
        protocolVersion = Int64(envelope.protocolVersion)
    }
}

/// Where cloud records are stored. The real one talks to CloudKit; tests use a stand-in.
@MainActor
protocol IntegrationCloudStore {
    var isAvailable: Bool { get }
    func save(_ record: IntegrationCloudRecord) async throws
}

/// Across devices: a dedicated private CloudKit container that holds nothing but these events
/// (`iCloud.AnnaLoseva.CalmMood`) — never the diary's container. One record per event, named by
/// the event id, so re-saving overwrites the same record.
///
/// NOT verified against real iCloud: the simulator has no account. Needs two physical devices.
@MainActor
final class CloudKitIntegrationStore: IntegrationCloudStore {
    private let zoneID = CKRecordZone.ID(zoneName: MoodPomodoroContract.cloudZoneName, ownerName: CKCurrentUserDefaultName)
    private var zoneReady = false
    /// Created only when first needed: touching CKContainer without iCloud set up logs a client bug.
    private lazy var database = CKContainer(identifier: MoodPomodoroContract.cloudContainerID).privateCloudDatabase

    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    var isAvailable: Bool {
        !Self.isRunningTests
            && PersistenceController.cloudKitEnabledInThisBuild
            && FileManager.default.ubiquityIdentityToken != nil
    }

    func save(_ record: IntegrationCloudRecord) async throws {
        try await ensureZone()
        let id = CKRecord.ID(recordName: record.recordName, zoneID: zoneID)
        let cloud = CKRecord(recordType: MoodPomodoroContract.cloudRecordType, recordID: id)
        cloud["recipient"] = record.recipient
        cloud["payload"] = record.payload
        cloud["createdAt"] = record.createdAt
        cloud["protocolVersion"] = record.protocolVersion
        let result = try await database.modifyRecords(saving: [cloud], deleting: [], savePolicy: .allKeys)
        if case .failure(let error)? = result.saveResults[id] { throw error }
    }

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        zoneReady = true
    }
}

@MainActor
struct CloudChannel: SilentIntegrationChannel {
    let store: IntegrationCloudStore

    var isAvailable: Bool { store.isAvailable }

    func send(_ envelope: IntegrationEnvelope) async -> Bool {
        guard let record = IntegrationCloudRecord(envelope) else { return false }
        do {
            try await store.save(record)
            return true
        } catch {
            return false   // offline or iCloud busy: stays queued, same record id next time
        }
    }
}

// MARK: - The real transport

/// Shared mailbox (this device) and iCloud (other devices), then — only for an explicit tap and
/// only if neither could take it — ToDo List's own link.
///
/// An event counts as delivered when EVERY available silent channel took it, so a transient
/// iCloud failure is retried instead of being forgotten because the mailbox worked.
@MainActor
struct TodoIntegrationRouter: TodoIntegrationTransport {
    var channels: [SilentIntegrationChannel]
    var link = URLSchemeTodoTransport()
    var mailbox: IntegrationMailbox?

    init(
        channels: [SilentIntegrationChannel]? = nil,
        mailbox: IntegrationMailbox? = SharedMailboxChannel.groupMailbox()
    ) {
        self.mailbox = mailbox
        self.channels = channels ?? [
            SharedMailboxChannel(mailbox: mailbox),
            CloudChannel(store: CloudKitIntegrationStore())
        ]
    }

    var isTodoAppInstalled: Bool { link.isTodoAppInstalled }
    var deliversSilently: Bool { channels.contains { $0.isAvailable } }

    func canDeliver(_ type: TodoIntegrationEventType) -> Bool {
        deliversSilently || (TodoEnvelopeMapper.isExplicitUserAction(type) && isTodoAppInstalled)
    }

    func deliver(_ event: TodoIntegrationEvent, userInitiated: Bool) async -> TodoDeliveryResult {
        guard let envelope = TodoEnvelopeMapper.envelope(for: event) else { return .unavailable }

        let available = channels.filter { $0.isAvailable }
        if !available.isEmpty {
            var allTook = true
            for channel in available {
                if await channel.send(envelope) == false { allTook = false }
            }
            if allTook { return .delivered }
        }

        // Switching apps is only ever the answer to a tap on an explicit action.
        guard userInitiated, TodoEnvelopeMapper.isExplicitUserAction(event.type) else { return .unavailable }
        return await link.openLink(for: envelope, event: event)
    }

    func receipts(for events: [TodoIntegrationEvent]) -> [String: IntegrationAckStatus] {
        guard let mailbox else { return [:] }
        var result: [String: IntegrationAckStatus] = [:]
        for event in events {
            if let ack = mailbox.ack(for: TodoEnvelopeMapper.eventUUID(for: event.id)) {
                result[event.id] = ack.status
            }
        }
        return result
    }
}

// MARK: - The link ToDo List understands

/// Opens ToDo List. Because it switches apps, it is used only from a tap on an explicit action.
@MainActor
struct URLSchemeTodoTransport {
    var isTodoAppInstalled: Bool {
        guard let url = URL(string: "\(TodoIntegrationContract.todoScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// `calmday://complete?taskId=` for a completion (older, event-less link that ToDo List
    /// still honours as "set done"), `calmday://integration?…` for everything else.
    func openLink(for envelope: IntegrationEnvelope, event: TodoIntegrationEvent) async -> TodoDeliveryResult {
        guard isTodoAppInstalled else { return .unavailable }
        let url: URL?
        switch event.type {
        case .taskCompletionRequested:
            url = Self.completionURL(for: event)
        default:
            url = IntegrationEventURL.make(envelope)
        }
        guard let url else { return .unavailable }
        return await UIApplication.shared.open(url) ? .handedOff : .unavailable
    }

    static func completionURL(for event: TodoIntegrationEvent) -> URL? {
        guard let taskID = event.taskID else { return nil }
        var components = URLComponents()
        components.scheme = TodoIntegrationContract.todoScheme
        components.host = TodoIntegrationContract.completeHost
        components.queryItems = [URLQueryItem(name: "taskId", value: taskID.uuidString)]
        return components.url
    }

    static func createDoneURL(for event: TodoIntegrationEvent) -> URL? {
        TodoEnvelopeMapper.envelope(for: event).flatMap { IntegrationEventURL.make($0) }
    }
}
