//
//  TodoIntegrationTransport.swift
//  Mood Pomodoro
//

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
        guard event.type == .taskCompletionRequested, let taskID = event.taskID else { return .unavailable }
        var components = URLComponents()
        components.scheme = TodoIntegrationContract.todoScheme
        components.host = TodoIntegrationContract.completeHost
        components.queryItems = [URLQueryItem(name: "taskId", value: taskID.uuidString)]
        guard let url = components.url, isTodoAppInstalled else { return .unavailable }
        return await UIApplication.shared.open(url) ? .handedOff : .unavailable
    }
}
