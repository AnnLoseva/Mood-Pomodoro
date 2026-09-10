//
//  NotificationScheduler.swift
//  Mood Pomodoro
//

import Foundation
import UserNotifications

/// Schedules and cancels the local "Как ты?" reminders for a session.
///
/// Sessions never rely on the app staying alive: every reminder is a plain
/// `UNCalendarNotificationTrigger` fired by iOS, computed from the session's
/// `scheduleAnchor` timestamp. iOS caps an app at 64 pending local
/// notifications, so only a batch is scheduled up front; `topUpIfNeeded`
/// schedules the next batch once the pending count runs low (called on
/// foreground and whenever a reminder fires).
enum NotificationScheduler {
    static let categoryIdentifier = "MOOD_CHECKIN"
    private static let identifierPrefix = "session."
    private static let maxScheduledPerBatch = 60
    private static let topUpThreshold = 5

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    static func registerCategories() {
        let actions = Mood.orderedCases.map { mood in
            UNNotificationAction(
                identifier: actionIdentifier(for: mood),
                title: "\(mood.emoji) \(mood.label)",
                options: []
            )
        }
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func actionIdentifier(for mood: Mood) -> String { "mood.\(mood.rawValue)" }

    static func mood(fromActionIdentifier identifier: String) -> Mood? {
        guard identifier.hasPrefix("mood.") else { return nil }
        return Mood(rawValue: String(identifier.dropFirst("mood.".count)))
    }

    private static func identifier(sessionID: UUID, checkpoint: Int) -> String {
        "\(identifierPrefix)\(sessionID.uuidString).checkin.\(checkpoint)"
    }

    /// Schedules reminders for checkpoints `fromCheckpoint..<fromCheckpoint+maxScheduledPerBatch`,
    /// each firing at `referenceStart + checkpoint * interval`.
    static func scheduleUpcoming(for session: FocusSession, fromCheckpoint: Int, referenceStart: Date) async {
        guard session.isActive, !session.isPaused else { return }
        let interval = session.checkInInterval
        guard interval > 0 else { return }

        let center = UNUserNotificationCenter.current()
        var checkpoint = fromCheckpoint
        let limit = fromCheckpoint + maxScheduledPerBatch
        while checkpoint < limit {
            defer { checkpoint += 1 }
            let fireDate = referenceStart.addingTimeInterval(interval * Double(checkpoint))
            guard fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Mood Pomodoro"
            content.body = "Как ты?"
            content.categoryIdentifier = categoryIdentifier
            content.threadIdentifier = session.id.uuidString
            content.sound = .default
            content.userInfo = [
                "sessionID": session.id.uuidString,
                "checkpoint": checkpoint
            ]

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(sessionID: session.id, checkpoint: checkpoint),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancelAll(for sessionID: UUID) {
        let center = UNUserNotificationCenter.current()
        let prefix = "\(identifierPrefix)\(sessionID.uuidString)."
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Tops up scheduled reminders if fewer than `topUpThreshold` remain pending.
    /// Call on app foreground and after handling a delivered reminder.
    static func topUpIfNeeded(for session: FocusSession) async {
        guard session.isActive, !session.isPaused else { return }
        let pending = await pendingRequests(for: session.id)
        guard pending.count < topUpThreshold else { return }
        let nextCheckpoint = nextCheckpointIndex(existing: pending, sessionID: session.id)
        await scheduleUpcoming(for: session, fromCheckpoint: nextCheckpoint, referenceStart: session.scheduleAnchor)
    }

    private static func pendingRequests(for sessionID: UUID) async -> [UNNotificationRequest] {
        let prefix = "\(identifierPrefix)\(sessionID.uuidString)."
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix(prefix) }
    }

    private static func nextCheckpointIndex(existing: [UNNotificationRequest], sessionID: UUID) -> Int {
        let prefix = "\(identifierPrefix)\(sessionID.uuidString).checkin."
        let indices = existing.compactMap { request -> Int? in
            guard request.identifier.hasPrefix(prefix) else { return nil }
            return Int(request.identifier.dropFirst(prefix.count))
        }
        return (indices.max() ?? 0) + 1
    }
}
