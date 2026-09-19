//
//  TodoIntegrationCoordinator.swift
//  Mood Pomodoro
//

import Foundation
import Observation

/// What the finish sheet is about.
struct TodoSessionPrompt: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The session came from a task: "Продолжу позже" or "Готово".
        case linkedTask(taskID: UUID, title: String)
        /// A standalone activity: "Добавить в сделанное?".
        case standalone(activity: String)
    }

    enum Progress: Equatable {
        case none
        /// Saved but not given to the other app yet.
        case queued
        /// Given to the other app. Nothing more is claimed than that.
        case handedOff
    }

    var id: UUID { sessionID }
    let sessionID: UUID
    let kind: Kind
    let endedAt: Date
    let createdAt: Date
    var progress: Progress = .none
}

/// The other-app side of Mood Pomodoro, in one place and out of the views:
/// reads an incoming request, remembers what to tell ToDo List, and hands it
/// over when the user asks. The timer, notifications and Live Activity never
/// touch it — with ToDo List absent, the app is exactly what it was.
@MainActor
@Observable
final class TodoIntegrationCoordinator {
    /// A task waiting to become a session on the New Session screen.
    private(set) var pendingFocus: TodoFocusRequest?
    /// Shown on the running session when a request arrives during it.
    private(set) var conflict: Conflict?
    var prompt: TodoSessionPrompt?

    struct Conflict: Equatable {
        let runningActivity: String
        let requestedTitle: String
    }

    @ObservationIgnored let outbox: TodoIntegrationOutbox
    @ObservationIgnored private let transport: TodoIntegrationTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    private static let consumedKey = "todo.integration.consumedRequestIDs"
    private static let consumedLimit = 50
    /// A finish sheet older than this is not offered any more: the moment to
    /// say "готово" has passed and nothing should nag.
    static let promptLifetime: TimeInterval = 30 * 60

    init(
        outbox: TodoIntegrationOutbox? = nil,
        transport: TodoIntegrationTransport? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        self.outbox = outbox ?? TodoIntegrationOutbox()
        self.transport = transport ?? URLSchemeTodoTransport()
        self.defaults = defaults
        self.now = now
    }

    var isTodoAppInstalled: Bool { transport.isTodoAppInstalled }

    // MARK: - Incoming: start for a task

    /// Reads a link. Returns true if it was a valid request for this app
    /// (so the caller can bring the start screen forward); false for anything
    /// else, which is ignored without a trace.
    ///
    /// Opening a link never starts a session — it only prepares the start
    /// screen — so a re-delivered link cannot create a second one.
    @discardableResult
    func handle(url: URL, activeSession: FocusSession?) -> Bool {
        guard case .success(let request) = TodoFocusRequest.parse(url) else { return false }
        if let requestID = request.requestID, consumedRequestIDs.contains(requestID) { return true }

        if let active = activeSession {
            // Never a second session on top, never an automatic end.
            if active.sourceTaskID == request.taskID {
                pendingFocus = nil
                conflict = nil
            } else {
                pendingFocus = request
                conflict = Conflict(runningActivity: active.activity, requestedTitle: request.title)
            }
            return true
        }
        pendingFocus = request
        conflict = nil
        return true
    }

    /// The session was started from the pending task.
    func focusDidStart(_ request: TodoFocusRequest) {
        remember(request)
        if pendingFocus?.taskID == request.taskID { pendingFocus = nil }
        conflict = nil
    }

    /// The user set the task aside ("Не сейчас", or unlinked it).
    func dismissFocus() {
        if let request = pendingFocus { remember(request) }
        pendingFocus = nil
        conflict = nil
    }

    private var consumedRequestIDs: [String] {
        defaults.stringArray(forKey: Self.consumedKey) ?? []
    }

    private func remember(_ request: TodoFocusRequest) {
        guard let requestID = request.requestID else { return }
        var ids = consumedRequestIDs.filter { $0 != requestID }
        ids.append(requestID)
        defaults.set(Array(ids.suffix(Self.consumedLimit)), forKey: Self.consumedKey)
    }

    // MARK: - From the session manager

    func handle(lifecycle event: SessionLifecycleEvent) {
        switch event {
        case .finished(let session):
            sessionDidFinish(session)
        case .deleted(let sessionID, let taskID):
            outbox.enqueue(.sessionDeleted(sessionID: sessionID, taskID: taskID, at: now()))
            if prompt?.sessionID == sessionID { prompt = nil }
        }
    }

    private func sessionDidFinish(_ session: FocusSession) {
        // A typed-in entry is a record, not a session that just ended.
        guard session.origin == .timer else { return }
        let endedAt = session.endDate ?? now()

        if let taskID = session.sourceTaskID {
            outbox.enqueue(.sessionFinished(session, at: now()))
            prompt = TodoSessionPrompt(
                sessionID: session.id,
                kind: .linkedTask(taskID: taskID, title: session.sourceTaskTitle ?? session.activity),
                endedAt: endedAt,
                createdAt: now()
            )
        } else if transport.canDeliver(.createDoneTaskRequested), transport.isTodoAppInstalled {
            // Offered only when ToDo List can actually take it; otherwise the
            // question would lead nowhere.
            prompt = TodoSessionPrompt(
                sessionID: session.id,
                kind: .standalone(activity: session.activity),
                endedAt: endedAt,
                createdAt: now()
            )
        }
    }

    /// A linked session was corrected: tell the other app the new state of
    /// the same session rather than adding another.
    func sessionDidUpdate(_ session: FocusSession) {
        guard session.sourceTaskID != nil, session.state == .completed else { return }
        outbox.enqueue(.sessionUpdated(session, at: now()))
    }

    // MARK: - The two explicit answers

    /// "Готово": ask ToDo List to mark the task done. Saved first, handed
    /// over second; pressing again is the same operation, not a new one.
    func requestCompletion() async {
        guard let current = prompt, case .linkedTask(let taskID, let title) = current.kind else { return }
        let event = outbox.enqueue(.completionRequested(taskID: taskID, sessionID: current.sessionID, title: title, at: now()))
        await deliver(event)
    }

    /// "Добавить": ask ToDo List for one done entry for this activity.
    func requestCreateDone() async {
        guard let current = prompt, case .standalone(let activity) = current.kind else { return }
        let event = outbox.enqueue(.createDoneRequested(sessionID: current.sessionID, title: activity, endedAt: current.endedAt, at: now()))
        await deliver(event)
    }

    private func deliver(_ event: TodoIntegrationEvent) async {
        guard event.delivery == .queued else {
            setProgress(.handedOff)
            return
        }
        guard transport.canDeliver(event.type) else {
            setProgress(.queued)
            return
        }
        outbox.markAttempted(event.id, at: now())
        switch await transport.deliver(event) {
        case .handedOff:
            outbox.markHandedOff(event.id, at: now())
            setProgress(.handedOff)
        case .unavailable:
            setProgress(.queued)
        }
    }

    private func setProgress(_ progress: TodoSessionPrompt.Progress) {
        prompt?.progress = progress
    }

    func dismissPrompt() {
        prompt = nil
    }

    // MARK: - Lifecycle

    /// On becoming active: drop a stale finish sheet, and give a channel that
    /// works without switching apps whatever is waiting. With none today, the
    /// second half does nothing — nothing is ever opened behind the user's back.
    func applicationDidBecomeActive() async {
        if let current = prompt, current.progress == .none,
           now().timeIntervalSince(current.createdAt) > Self.promptLifetime {
            prompt = nil
        }
        guard transport.deliversSilently else { return }
        for event in outbox.queued(where: transport.canDeliver) {
            outbox.markAttempted(event.id, at: now())
            if await transport.deliver(event) == .handedOff {
                outbox.markHandedOff(event.id, at: now())
            }
        }
    }
}
