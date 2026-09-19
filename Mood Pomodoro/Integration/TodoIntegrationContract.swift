//
//  TodoIntegrationContract.swift
//  Mood Pomodoro
//

import Foundation

/// Everything Mood Pomodoro knows about the ToDo List app ("CalmDay").
///
/// **What is agreed and what is not.** The two apps are separate projects.
/// What exists in ToDo List today, and is mirrored here exactly:
///
/// * it opens `moodpomodoro://focus?taskId=<UUID>&title=<text>&source=calmday`
///   to start a focus session (`MoodPomodoroBridge`);
/// * it accepts `calmday://complete?taskId=<UUID>`, which marks the task done
///   and does nothing if it already is (`DeepLink`, `RootView.handle`).
///
/// ToDo List has since published its contract
/// (`docs/MOOD_POMODORO_INTEGRATION.md`, shared file `MoodPomodoroContract.swift`,
/// copied here byte for byte). Of it, only `createDoneTaskRequested` over the
/// `calmday://integration` link is wired up. The session events and the
/// App Group / CloudKit channels are not, so those stay behind `canDeliver`
/// and nothing pretends to reach an app that cannot yet receive it.
enum TodoIntegrationContract {
    /// Version of the event envelope this app writes to its outbox.
    static let schemaVersion = 1

    /// Scheme this app registers (Info.plist `CFBundleURLTypes`).
    static let incomingScheme = "moodpomodoro"
    static let focusHost = "focus"

    /// Scheme of the ToDo List app (Info.plist `LSApplicationQueriesSchemes`).
    static let todoScheme = "calmday"
    static let completeHost = "complete"

    /// The value ToDo List puts in `source`.
    static let sourceApp = "calmday"

    /// What ToDo List's own placeholder names. It is not in either app's
    /// entitlements, so no code here relies on it being reachable.
    static let appGroupIdentifier = "group.com.annaloseva.calmmood"

    static let maxTitleLength = 200

    /// Whether the other app can receive this kind of event *today*.
    static func canDeliver(_ type: TodoIntegrationEventType) -> Bool {
        switch type {
        case .taskCompletionRequested, .createDoneTaskRequested: return true
        case .sessionFinished, .sessionUpdated, .sessionDeleted: return false
        }
    }
}

// MARK: - Incoming: start a session for a task

/// A request from ToDo List to begin a session for one of its tasks.
///
/// Holds only what the link carries. It never chooses a type or an interval
/// for the session: the same task can be учёба one day and обязательная
/// работа the next.
struct TodoFocusRequest: Equatable, Sendable, Identifiable {
    let taskID: UUID
    let title: String
    let source: String
    /// Optional; when the sender supplies one, a re-delivered link is
    /// recognised and not shown twice.
    let requestID: String?

    var id: UUID { taskID }

    enum Failure: Error, Equatable {
        case wrongScheme
        case wrongAction
        case missingTaskID
        case invalidTaskID
        case missingTitle
        case unknownSource
    }

    static func parse(_ url: URL) -> Result<TodoFocusRequest, Failure> {
        guard url.scheme?.lowercased() == TodoIntegrationContract.incomingScheme else { return .failure(.wrongScheme) }
        guard url.host?.lowercased() == TodoIntegrationContract.focusHost else { return .failure(.wrongAction) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard let rawID = value("taskId"), !rawID.isEmpty else { return .failure(.missingTaskID) }
        guard let taskID = UUID(uuidString: rawID) else { return .failure(.invalidTaskID) }

        let title = sanitized(value("title") ?? "")
        guard !title.isEmpty else { return .failure(.missingTitle) }

        let source = value("source") ?? TodoIntegrationContract.sourceApp
        guard source == TodoIntegrationContract.sourceApp else { return .failure(.unknownSource) }

        let requestID = value("requestId").flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
        return .success(TodoFocusRequest(taskID: taskID, title: title, source: source, requestID: requestID))
    }

    /// Single line, no control characters, bounded — the title is text from
    /// outside the app and ends up in the session name.
    private static func sanitized(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(TodoIntegrationContract.maxTitleLength))
    }
}

// MARK: - Outgoing events

enum TodoIntegrationEventType: String, Codable, Sendable {
    /// The user said the task is done. Never inferred from a timer ending.
    case taskCompletionRequested
    /// The user asked to add a standalone activity to ToDo List's "done".
    case createDoneTaskRequested
    case sessionFinished
    case sessionUpdated
    case sessionDeleted
}

enum TodoIntegrationDelivery: String, Codable, Sendable {
    /// Saved, not yet given to the other app.
    case queued
    /// Given to the other app (its link was opened). There is no
    /// acknowledgement channel, so this is as far as the state can honestly go.
    case handedOff
}

/// One thing to tell ToDo List, carrying only the minimum: ids, a title, and
/// durations. Never mood, sleep, medication, cycle or diary content.
struct TodoIntegrationEvent: Codable, Equatable, Identifiable, Sendable {
    /// Stable for the operation, so the same tap or the same session always
    /// yields the same id and can never become two operations.
    var id: String
    var type: TodoIntegrationEventType
    var schemaVersion: Int = TodoIntegrationContract.schemaVersion
    var createdAt: Date
    var taskID: UUID?
    var sessionID: UUID?
    /// Task title for `taskCompletionRequested`, activity name for
    /// `createDoneTaskRequested`.
    var title: String?
    /// Active time only — pauses excluded — from `activeWorkDuration`.
    var activeDurationSeconds: Double?
    var startedAt: Date?
    var endedAt: Date?
    /// The session's `updatedAt` at the time, so a receiver can tell a newer
    /// state of the same session from an older one.
    var revision: Date?
    var delivery: TodoIntegrationDelivery = .queued
    var attempts: Int = 0
    var lastAttemptAt: Date?

    /// Events about one session replace one another; a completion request
    /// and a create-done request are their own operations.
    var coalescingKey: String {
        switch type {
        case .sessionFinished, .sessionUpdated, .sessionDeleted:
            return "session:\(sessionID?.uuidString ?? id)"
        case .taskCompletionRequested, .createDoneTaskRequested:
            return id
        }
    }

    // MARK: Constructors (ids are derived, never random)

    static func completionRequested(taskID: UUID, sessionID: UUID, title: String?, at date: Date) -> TodoIntegrationEvent {
        TodoIntegrationEvent(
            id: "taskCompletionRequested:\(taskID.uuidString):\(sessionID.uuidString)",
            type: .taskCompletionRequested,
            createdAt: date,
            taskID: taskID,
            sessionID: sessionID,
            title: title
        )
    }

    static func createDoneRequested(sessionID: UUID, title: String, endedAt: Date, at date: Date) -> TodoIntegrationEvent {
        TodoIntegrationEvent(
            id: "createDoneTaskRequested:\(sessionID.uuidString)",
            type: .createDoneTaskRequested,
            createdAt: date,
            sessionID: sessionID,
            title: title,
            endedAt: endedAt
        )
    }

    static func sessionFinished(_ session: FocusSession, at date: Date) -> TodoIntegrationEvent {
        let end = session.endDate ?? date
        return TodoIntegrationEvent(
            id: "sessionFinished:\(session.id.uuidString)",
            type: .sessionFinished,
            createdAt: date,
            taskID: session.sourceTaskID,
            sessionID: session.id,
            activeDurationSeconds: session.activeWorkDuration(asOf: end),
            startedAt: session.startDate,
            endedAt: end,
            revision: session.updatedAt
        )
    }

    static func sessionUpdated(_ session: FocusSession, at date: Date) -> TodoIntegrationEvent {
        let end = session.endDate ?? date
        return TodoIntegrationEvent(
            id: "sessionUpdated:\(session.id.uuidString):\(Int(session.updatedAt.timeIntervalSince1970 * 1000))",
            type: .sessionUpdated,
            createdAt: date,
            taskID: session.sourceTaskID,
            sessionID: session.id,
            activeDurationSeconds: session.activeWorkDuration(asOf: end),
            startedAt: session.startDate,
            endedAt: end,
            revision: session.updatedAt
        )
    }

    static func sessionDeleted(sessionID: UUID, taskID: UUID, at date: Date) -> TodoIntegrationEvent {
        TodoIntegrationEvent(
            id: "sessionDeleted:\(sessionID.uuidString)",
            type: .sessionDeleted,
            createdAt: date,
            taskID: taskID,
            sessionID: sessionID,
            revision: date
        )
    }
}

/// What the session manager reports, in terms the integration understands.
enum SessionLifecycleEvent {
    case finished(FocusSession)
    case deleted(sessionID: UUID, taskID: UUID)
}
