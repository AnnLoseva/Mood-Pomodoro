//
//  TodoIntegrationTransport.swift
//  Mood Pomodoro
//

import CryptoKit
import Foundation
import UIKit

enum TodoDeliveryResult: Equatable {
    /// The other app was given the event.
    case handedOff
    /// It cannot be reached right now (not installed, no channel). The event
    /// stays queued.
    case unavailable
}

/// How an event reaches ToDo List. Kept behind a protocol so the day the two
/// apps agree on a silent channel (a shared container, CloudKit) it is one
/// new type, and the queue, the prompts and the tests are unchanged.
@MainActor
protocol TodoIntegrationTransport {
    /// Whether ToDo List is on this device at all — decides if the app shows
    /// anything about it.
    var isTodoAppInstalled: Bool { get }
    /// True only for a channel that delivers without switching apps. Such a
    /// transport may be used from a background flush; one that opens the
    /// other app must only ever run from a tap.
    var deliversSilently: Bool { get }
    func canDeliver(_ type: TodoIntegrationEventType) -> Bool
    func deliver(_ event: TodoIntegrationEvent) async -> TodoDeliveryResult
}

/// The one channel ToDo List has today: `calmday://complete?taskId=<UUID>`.
/// It opens ToDo List, which marks that task done (and does nothing if it
/// already is — so a repeat is harmless). Because it switches apps, it is
/// only ever used for an explicit "Готово".
@MainActor
struct URLSchemeTodoTransport: TodoIntegrationTransport {
    var deliversSilently: Bool { false }

    var isTodoAppInstalled: Bool {
        guard let url = URL(string: "\(TodoIntegrationContract.todoScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func canDeliver(_ type: TodoIntegrationEventType) -> Bool {
        TodoIntegrationContract.canDeliver(type)
    }

    func deliver(_ event: TodoIntegrationEvent) async -> TodoDeliveryResult {
        switch event.type {
        case .taskCompletionRequested:
            return await openCompletionLink(event)
        case .createDoneTaskRequested:
            return await openCreateDoneLink(event)
        case .sessionFinished, .sessionUpdated, .sessionDeleted:
            return .unavailable
        }
    }

    /// `calmday://integration?v=1&event=…` — the contract's fallback path D:
    /// one whole event, applied by ToDo List once per `requestID`.
    private func openCreateDoneLink(_ event: TodoIntegrationEvent) async -> TodoDeliveryResult {
        guard isTodoAppInstalled, let url = Self.createDoneURL(for: event) else { return .unavailable }
        return await UIApplication.shared.open(url) ? .handedOff : .unavailable
    }

    static func createDoneURL(for event: TodoIntegrationEvent) -> URL? {
        guard let sessionID = event.sessionID,
              let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let occurredAt = event.endedAt else { return nil }
        // Both ids are derived from the session, so pressing again re-sends the
        // same request and ToDo List reports a duplicate instead of adding another.
        let envelope = IntegrationEnvelope(
            eventID: stableUUID(for: event.id),
            createdAt: event.createdAt,
            origin: IntegrationOrigin(app: MoodPomodoroContract.moodSource),
            payload: .createDoneTaskRequested(
                requestID: sessionID,
                title: String(title.prefix(MoodPomodoroContract.maxTitleLength)),
                occurredAt: occurredAt,
                session: nil
            )
        )
        return IntegrationEventURL.make(envelope)
    }

    private static func stableUUID(for string: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data(string.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func openCompletionLink(_ event: TodoIntegrationEvent) async -> TodoDeliveryResult {
        guard let taskID = event.taskID else { return .unavailable }
        var components = URLComponents()
        components.scheme = TodoIntegrationContract.todoScheme
        components.host = TodoIntegrationContract.completeHost
        components.queryItems = [URLQueryItem(name: "taskId", value: taskID.uuidString)]
        guard let url = components.url, isTodoAppInstalled else { return .unavailable }
        return await UIApplication.shared.open(url) ? .handedOff : .unavailable
    }
}
