//
//  MoodPomodoroContract.swift
//
//  SHARED CONTRACT between the two separate apps "ToDo List" (calmday) and
//  "Mood Pomodoro". The file is deliberately dependency-free: Foundation only —
//  no SwiftData, SwiftUI, UIKit or app logic — so it can be copied byte-for-byte into
//  the other repository.
//
//  Canonical copy:  ToDo-List/ToDo List/Integration/Contract/MoodPomodoroContract.swift
//  Specification:   ToDo-List/docs/MOOD_POMODORO_INTEGRATION.md
//
//  The types are `nonisolated` so they behave the same whatever default actor isolation
//  the host target uses.
//
//  Compatibility rule: both copies must have the same `contractRevision`. Any edit to
//  this file bumps it; a change that old readers can't understand also bumps
//  `protocolVersion`. See the specification, "Keeping the two copies in sync".
//

import Foundation

// MARK: - Constants

nonisolated public enum MoodPomodoroContract {
    /// Wire-format major version. Readers process only events whose `protocolVersion`
    /// equals this value; a greater value is acknowledged as `unsupported`.
    public static let protocolVersion = 1
    /// Version of this Swift file itself (bumped on every edit).
    public static let contractRevision = 1

    public static let todoScheme = "calmday"
    public static let moodScheme = "moodpomodoro"
    /// Value of the `source` query item in links sent by ToDo List.
    public static let todoSource = "calmday"
    public static let moodSource = "moodpomodoro"

    /// App Group shared on ONE device. Must be enabled in both targets.
    public static let appGroupID = "group.com.annaloseva.calmmood"

    /// A dedicated CloudKit container (private database) used ONLY for integration events
    /// between the user's devices. It must never be an app's own data container.
    public static let cloudContainerID = "iCloud.AnnaLoseva.CalmMood"
    public static let cloudZoneName = "MoodIntegration"
    public static let cloudRecordType = "IntegrationEvent"
    public static let cloudRecipientTodo = "calmday"

    /// Events older than this are `expired`; delivered records are pruned after it.
    public static let maxEventAge: TimeInterval = 30 * 24 * 3600
    /// How long a receiver waits for a not-yet-known task before answering `taskNotFound`.
    public static let taskLookupGrace: TimeInterval = 7 * 24 * 3600
    public static let maxTitleLength = 200
    public static let maxActiveSeconds = 24 * 3600
}

// MARK: - Events

nonisolated public enum IntegrationEventKind: String, Codable, CaseIterable, Sendable {
    /// Mood Pomodoro → ToDo List. A session ended or was corrected (upsert by sessionID+revision).
    case sessionFinished
    /// Mood Pomodoro → ToDo List. A session was deleted (tombstone by sessionID+revision).
    case sessionRemoved
    /// Mood Pomodoro → ToDo List. The user explicitly chose "Готово" for a linked task.
    case taskCompletionRequested
    /// Mood Pomodoro → ToDo List. The user explicitly chose "Добавить в сделанное" for an unlinked session.
    case createDoneTaskRequested
}

/// The facts about one focus session that ToDo List is allowed to know.
/// No mood, notes, health, activity type or check-ins.
nonisolated public struct IntegrationSession: Codable, Equatable, Sendable {
    /// Mood Pomodoro's own id of the session (`FocusSession.id`). Identity of the session.
    public var sessionID: UUID
    /// Strictly increasing per session on every change (correction, deletion, restoration).
    /// Recommended value: `Int64(updatedAt.timeIntervalSince1970 * 1000)`.
    public var revision: Int64
    public var startedAt: Date?
    public var endedAt: Date
    /// Active working time in whole seconds, pauses/breaks excluded. 0...86400.
    public var activeSeconds: Int

    public init(sessionID: UUID, revision: Int64, startedAt: Date?, endedAt: Date, activeSeconds: Int) {
        self.sessionID = sessionID
        self.revision = revision
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
    }
}

nonisolated public enum IntegrationPayload: Equatable, Sendable {
    case sessionFinished(taskID: UUID, session: IntegrationSession)
    case sessionRemoved(sessionID: UUID, revision: Int64)
    case taskCompletionRequested(taskID: UUID, sessionID: UUID?)
    case createDoneTaskRequested(requestID: UUID, title: String, occurredAt: Date, session: IntegrationSession?)

    public var kind: IntegrationEventKind {
        switch self {
        case .sessionFinished: .sessionFinished
        case .sessionRemoved: .sessionRemoved
        case .taskCompletionRequested: .taskCompletionRequested
        case .createDoneTaskRequested: .createDoneTaskRequested
        }
    }
}

nonisolated public struct IntegrationOrigin: Codable, Equatable, Sendable {
    /// `MoodPomodoroContract.moodSource` or `.todoSource`.
    public var app: String
    /// Optional random per-install id of the sending device (diagnostics only).
    public var deviceID: String?

    public init(app: String, deviceID: String? = nil) {
        self.app = app
        self.deviceID = deviceID
    }
}

nonisolated public enum IntegrationDecodeError: Error, Equatable {
    case unsupportedProtocol(Int)
    case unknownKind(String)
    case malformed(String)
}

/// One event on the wire. JSON shape:
/// `{"protocolVersion":1,"eventID":"…","kind":"sessionFinished","createdAt":"…","origin":{…},"payload":{…}}`
nonisolated public struct IntegrationEnvelope: Equatable, Sendable, Codable {
    public var protocolVersion: Int
    /// Unique id of this delivery attempt's event. Redelivery re-sends the SAME eventID.
    public var eventID: UUID
    /// When the user action / session change happened (not when it was delivered).
    public var createdAt: Date
    public var origin: IntegrationOrigin
    public var payload: IntegrationPayload

    public init(
        protocolVersion: Int = MoodPomodoroContract.protocolVersion,
        eventID: UUID = UUID(),
        createdAt: Date,
        origin: IntegrationOrigin,
        payload: IntegrationPayload
    ) {
        self.protocolVersion = protocolVersion
        self.eventID = eventID
        self.createdAt = createdAt
        self.origin = origin
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, eventID, kind, createdAt, origin, payload
    }

    nonisolated private struct SessionFinishedBody: Codable {
        var taskID: UUID
        var session: IntegrationSession
    }
    nonisolated private struct SessionRemovedBody: Codable {
        var sessionID: UUID
        var revision: Int64
    }
    nonisolated private struct TaskCompletionBody: Codable {
        var taskID: UUID
        var sessionID: UUID?
    }
    nonisolated private struct CreateDoneBody: Codable {
        var requestID: UUID
        var title: String
        var occurredAt: Date
        var session: IntegrationSession?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try c.decode(Int.self, forKey: .protocolVersion)
        eventID = try c.decode(UUID.self, forKey: .eventID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        origin = try c.decode(IntegrationOrigin.self, forKey: .origin)

        let rawKind = try c.decode(String.self, forKey: .kind)
        guard let kind = IntegrationEventKind(rawValue: rawKind) else {
            throw IntegrationDecodeError.unknownKind(rawKind)
        }
        switch kind {
        case .sessionFinished:
            let body = try c.decode(SessionFinishedBody.self, forKey: .payload)
            payload = .sessionFinished(taskID: body.taskID, session: body.session)
        case .sessionRemoved:
            let body = try c.decode(SessionRemovedBody.self, forKey: .payload)
            payload = .sessionRemoved(sessionID: body.sessionID, revision: body.revision)
        case .taskCompletionRequested:
            let body = try c.decode(TaskCompletionBody.self, forKey: .payload)
            payload = .taskCompletionRequested(taskID: body.taskID, sessionID: body.sessionID)
        case .createDoneTaskRequested:
            let body = try c.decode(CreateDoneBody.self, forKey: .payload)
            payload = .createDoneTaskRequested(
                requestID: body.requestID, title: body.title, occurredAt: body.occurredAt, session: body.session
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(protocolVersion, forKey: .protocolVersion)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(payload.kind.rawValue, forKey: .kind)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(origin, forKey: .origin)
        switch payload {
        case let .sessionFinished(taskID, session):
            try c.encode(SessionFinishedBody(taskID: taskID, session: session), forKey: .payload)
        case let .sessionRemoved(sessionID, revision):
            try c.encode(SessionRemovedBody(sessionID: sessionID, revision: revision), forKey: .payload)
        case let .taskCompletionRequested(taskID, sessionID):
            try c.encode(TaskCompletionBody(taskID: taskID, sessionID: sessionID), forKey: .payload)
        case let .createDoneTaskRequested(requestID, title, occurredAt, session):
            try c.encode(
                CreateDoneBody(requestID: requestID, title: title, occurredAt: occurredAt, session: session),
                forKey: .payload
            )
        }
    }
}

// MARK: - Acknowledgements (ToDo List → Mood Pomodoro)

nonisolated public enum IntegrationAckStatus: String, Codable, CaseIterable, Sendable {
    /// The event changed state (or was valid and required no change, see `detail`).
    case applied
    /// This eventID (or the same requestID / session revision) was already handled.
    case duplicate
    /// A newer revision of the same session was already known.
    case stale
    /// The referenced task does not exist (after the grace period).
    case taskNotFound
    /// The event was understood but invalid (bad duration, empty title, …).
    case rejected
    /// Unknown protocolVersion or kind. Kept in quarantine, never applied.
    case unsupported
    /// Older than `maxEventAge`.
    case expired
}

/// Small receipt written by the receiver. Purely advisory: the sender may use it to stop
/// re-sending, but must never treat a missing ack as failure.
nonisolated public struct IntegrationAck: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var eventID: UUID
    public var status: IntegrationAckStatus
    public var processedAt: Date
    public var detail: String?
    /// Task the event ended up on (e.g. the task created by `createDoneTaskRequested`).
    public var taskID: UUID?

    public init(
        protocolVersion: Int = MoodPomodoroContract.protocolVersion,
        eventID: UUID,
        status: IntegrationAckStatus,
        processedAt: Date,
        detail: String? = nil,
        taskID: UUID? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.eventID = eventID
        self.status = status
        self.processedAt = processedAt
        self.detail = detail
        self.taskID = taskID
    }
}

// MARK: - JSON coding

nonisolated public enum IntegrationCoding {
    /// Just enough of an event to identify it even when the rest can't be understood.
    nonisolated public struct Header: Decodable, Equatable, Sendable {
        public var protocolVersion: Int
        public var eventID: UUID
        public var kind: String
        public var createdAt: Date
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Accepts ISO-8601 with or without fractional seconds.
    public static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = parse(string) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO-8601 date: \(string)")
                )
            }
            return date
        }
        return decoder
    }

    public static func encode(_ envelope: IntegrationEnvelope) throws -> Data {
        try makeEncoder().encode(envelope)
    }

    public static func encode(_ ack: IntegrationAck) throws -> Data {
        try makeEncoder().encode(ack)
    }

    public static func decodeAck(_ data: Data) throws -> IntegrationAck {
        try makeDecoder().decode(IntegrationAck.self, from: data)
    }

    public static func peekHeader(_ data: Data) throws -> Header {
        do {
            return try makeDecoder().decode(Header.self, from: data)
        } catch {
            throw IntegrationDecodeError.malformed("\(error)")
        }
    }

    /// Full decode. Throws `.unsupportedProtocol` before looking at the payload when the
    /// version is not ours, and `.unknownKind` for kinds this build doesn't know.
    public static func decode(_ data: Data) throws -> IntegrationEnvelope {
        let header = try peekHeader(data)
        guard header.protocolVersion == MoodPomodoroContract.protocolVersion else {
            throw IntegrationDecodeError.unsupportedProtocol(header.protocolVersion)
        }
        do {
            return try makeDecoder().decode(IntegrationEnvelope.self, from: data)
        } catch let error as IntegrationDecodeError {
            throw error
        } catch {
            throw IntegrationDecodeError.malformed("\(error)")
        }
    }
}

// MARK: - Deep links

/// `moodpomodoro://focus?v=1&taskId=<UUID>&title=<encoded>&source=calmday&requestId=<UUID>`
/// Sent by ToDo List to open Mood Pomodoro for one task instance. Contains nothing but
/// the task's id and title.
nonisolated public struct FocusLaunchRequest: Equatable, Sendable {
    public var taskID: UUID
    public var title: String
    public var requestID: UUID

    public init(taskID: UUID, title: String, requestID: UUID = UUID()) {
        self.taskID = taskID
        self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(MoodPomodoroContract.maxTitleLength))
        self.requestID = requestID
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = MoodPomodoroContract.moodScheme
        components.host = "focus"
        components.percentEncodedQueryItems = [
            .init(name: "v", value: String(MoodPomodoroContract.protocolVersion)),
            .init(name: "taskId", value: taskID.uuidString),
            .init(name: "title", value: IntegrationURLEncoding.encode(title)),
            .init(name: "source", value: MoodPomodoroContract.todoSource),
            .init(name: "requestId", value: requestID.uuidString)
        ]
        return components.url
    }

    /// Parses a link on the Mood Pomodoro side. Returns nil for anything that is not a
    /// well-formed focus link (wrong scheme/host, missing or invalid taskId, unknown version).
    public init?(url: URL) {
        guard url.scheme == MoodPomodoroContract.moodScheme, url.host == "focus",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let version = value("v"), Int(version) != MoodPomodoroContract.protocolVersion { return nil }
        guard let idString = value("taskId"), let taskID = UUID(uuidString: idString) else { return nil }
        self.init(
            taskID: taskID,
            title: value("title") ?? "",
            requestID: value("requestId").flatMap(UUID.init(uuidString:)) ?? UUID()
        )
    }
}

/// `calmday://integration?v=1&event=<base64url(JSON envelope)>`
/// Fallback delivery of one event by opening ToDo List. Always processed exactly like an
/// event found in the shared mailbox (same eventID → same idempotency).
nonisolated public enum IntegrationEventURL {
    public static func make(_ envelope: IntegrationEnvelope) -> URL? {
        guard let data = try? IntegrationCoding.encode(envelope) else { return nil }
        var components = URLComponents()
        components.scheme = MoodPomodoroContract.todoScheme
        components.host = "integration"
        components.percentEncodedQueryItems = [
            .init(name: "v", value: String(MoodPomodoroContract.protocolVersion)),
            .init(name: "event", value: base64URL(data))
        ]
        return components.url
    }

    public static func envelopeData(from url: URL) -> Data? {
        guard url.scheme == MoodPomodoroContract.todoScheme, url.host == "integration",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let encoded = items.first(where: { $0.name == "event" })?.value else { return nil }
        return data(fromBase64URL: encoded)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func data(fromBase64URL string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}

/// Query values are percent-encoded with the RFC 3986 "unreserved" set only, so `&`, `=`,
/// `+`, `#`, `%`, spaces, Cyrillic and emoji all survive. `+` is NOT a space.
nonisolated public enum IntegrationURLEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

// MARK: - Shared-folder mailbox (App Group)

/// A folder-based mailbox used through the App Group container (same device) and also as
/// ToDo List's own local queue. One event = one JSON file named `<EVENT-UUID>.json`.
///
///     <root>/to-todolist/    events for ToDo List (writer: Mood Pomodoro; remover: ToDo List)
///     <root>/acks/           receipts written by ToDo List (remover: whoever, after 30 days)
///     <root>/tmp/            staging area for atomic writes
///     <root>/quarantine/     events ToDo List could not understand
///
/// Writes are atomic (write to `tmp/`, then rename into place), so a reader never sees a
/// half-written file, and no locking between the two processes is needed.
nonisolated public struct IntegrationMailbox: Sendable {
    nonisolated public struct Entry: Sendable {
        public var url: URL
        public var data: Data
        public var header: IntegrationCoding.Header?
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `<app group container>/MoodIntegration/v1`
    public static func inGroupContainer(_ groupContainer: URL) -> IntegrationMailbox {
        IntegrationMailbox(root: groupContainer
            .appendingPathComponent("MoodIntegration", isDirectory: true)
            .appendingPathComponent("v\(MoodPomodoroContract.protocolVersion)", isDirectory: true))
    }

    public var inbox: URL { root.appendingPathComponent("to-todolist", isDirectory: true) }
    public var acks: URL { root.appendingPathComponent("acks", isDirectory: true) }
    public var tmp: URL { root.appendingPathComponent("tmp", isDirectory: true) }
    public var quarantineDirectory: URL { root.appendingPathComponent("quarantine", isDirectory: true) }

    private func ensure(_ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileName(_ eventID: UUID) -> String { "\(eventID.uuidString).json" }

    // Writer side ---------------------------------------------------------------------

    /// Queues an event. Re-queuing the same eventID is a no-op (the first copy wins).
    @discardableResult
    public func enqueue(_ envelope: IntegrationEnvelope) throws -> Bool {
        try enqueue(data: try IntegrationCoding.encode(envelope), eventID: envelope.eventID)
    }

    @discardableResult
    public func enqueue(data: Data, eventID: UUID) throws -> Bool {
        let fileManager = FileManager.default
        ensure(inbox)
        ensure(tmp)
        let destination = inbox.appendingPathComponent(fileName(eventID))
        if fileManager.fileExists(atPath: destination.path) { return false }

        let staged = tmp.appendingPathComponent("\(UUID().uuidString).tmp")
        try data.write(to: staged, options: .atomic)
        do {
            try fileManager.moveItem(at: staged, to: destination)
            return true
        } catch {
            try? fileManager.removeItem(at: staged)
            // Lost a race with another writer of the same event: that copy is as good as ours.
            if fileManager.fileExists(atPath: destination.path) { return false }
            throw error
        }
    }

    public func ack(for eventID: UUID) -> IntegrationAck? {
        guard let data = try? Data(contentsOf: acks.appendingPathComponent(fileName(eventID))) else { return nil }
        return try? IntegrationCoding.decodeAck(data)
    }

    // Reader side ---------------------------------------------------------------------

    /// Everything waiting, oldest event first. Unreadable files are skipped, not deleted.
    public func pendingEntries() -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let entries: [Entry] = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return Entry(url: url, data: data, header: try? IntegrationCoding.peekHeader(data))
            }
        return entries.sorted { lhs, rhs in
            switch (lhs.header, rhs.header) {
            case let (a?, b?):
                return a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.eventID.uuidString < b.eventID.uuidString
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.url.lastPathComponent < rhs.url.lastPathComponent
            }
        }
    }

    public func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }

    public func quarantine(_ entry: Entry) {
        ensure(quarantineDirectory)
        let destination = quarantineDirectory.appendingPathComponent(entry.url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: entry.url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    public func writeAck(_ ack: IntegrationAck) {
        ensure(acks)
        guard let data = try? IntegrationCoding.encode(ack) else { return }
        try? data.write(to: acks.appendingPathComponent(fileName(ack.eventID)), options: .atomic)
    }

    public func pruneAcks(olderThan cutoff: Date) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: acks, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
}
