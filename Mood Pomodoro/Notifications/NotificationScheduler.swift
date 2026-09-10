//
//  NotificationScheduler.swift
//  Mood Pomodoro
//

import Foundation
import UserNotifications

/// Schedules and cancels every local notification the app sends: the
/// periodic "Как ты?" reminders, the immediate "Почему так?" follow-up once
/// a mood is picked from a reminder, and the "Спасибо!" confirmation once a
/// reason is picked. All three stay fully actionable from the lock screen —
/// none of them need to open the app.
///
/// Reminders never rely on the app staying alive: each one is a plain
/// `UNCalendarNotificationTrigger` fired by iOS, computed from the session's
/// `scheduleAnchor` timestamp. iOS caps an app at 64 pending local
/// notifications, so only a batch is scheduled up front; `topUpIfNeeded`
/// schedules the next batch once the pending count runs low (called on
/// foreground and whenever a reminder fires).
enum NotificationScheduler {
    static let checkInCategory = "MOOD_CHECKIN"
    private static let reasonCategoryPrefix = "MOOD_REASON_"
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

    /// Registers the reminder category (5 mood actions) and one reason
    /// category per mood (its current reason list, from `reasons`). Call
    /// again whenever reasons change so the notification actions stay
    /// in sync with what the reason-editor screen shows.
    static func registerCategories(reasons: [Mood: [String]]) {
        let moodActions = Mood.orderedCases.map { mood in
            UNNotificationAction(identifier: actionIdentifier(for: mood), title: mood.emoji, options: [])
        }
        let checkInCategory = UNNotificationCategory(
            identifier: self.checkInCategory,
            actions: moodActions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let reasonCategories = Mood.orderedCases.map { mood -> UNNotificationCategory in
            let actions = (reasons[mood] ?? mood.defaultReasons).enumerated().map { index, reason in
                UNNotificationAction(identifier: reasonActionIdentifier(mood: mood, index: index), title: reason, options: [])
            }
            return UNNotificationCategory(
                identifier: reasonCategory(for: mood),
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        }

        UNUserNotificationCenter.current().setNotificationCategories(Set([checkInCategory] + reasonCategories))
    }

    static func reasonCategory(for mood: Mood) -> String { "\(reasonCategoryPrefix)\(mood.rawValue)" }

    static func actionIdentifier(for mood: Mood) -> String { "mood.\(mood.rawValue)" }

    static func mood(fromActionIdentifier identifier: String) -> Mood? {
        guard identifier.hasPrefix("mood.") else { return nil }
        return Mood(rawValue: String(identifier.dropFirst("mood.".count)))
    }

    static func reasonActionIdentifier(mood: Mood, index: Int) -> String { "reason.\(mood.rawValue).\(index)" }

    /// Parses a `reason.<mood>.<index>` action identifier back into its parts.
    static func parseReasonAction(_ identifier: String) -> (mood: Mood, index: Int)? {
        guard identifier.hasPrefix("reason.") else { return nil }
        let parts = identifier.dropFirst("reason.".count).split(separator: ".")
        guard parts.count == 2, let mood = Mood(rawValue: String(parts[0])), let index = Int(parts[1]) else { return nil }
        return (mood, index)
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
            content.title = "Как ты?"
            content.body = "Пора сделать маленький чек-ин 💚"
            content.categoryIdentifier = checkInCategory
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

    /// Fires ~1 second after a mood is picked from a reminder: "Почему так?"
    /// with that mood's reasons as tap-to-answer actions.
    static func scheduleReasonPrompt(sessionID: UUID, checkInID: UUID, mood: Mood) async {
        let content = UNMutableNotificationContent()
        content.title = "Почему так?"
        content.body = "\(mood.emoji) Отметь, что подходит"
        content.categoryIdentifier = reasonCategory(for: mood)
        content.threadIdentifier = sessionID.uuidString
        content.sound = .default
        content.userInfo = [
            "sessionID": sessionID.uuidString,
            "checkInID": checkInID.uuidString,
            "mood": mood.rawValue
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)\(sessionID.uuidString).reason.\(checkInID.uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Fires ~1 second after a reason is picked: a short "Спасибо!" confirmation, no actions.
    static func scheduleThankYou(sessionID: UUID) async {
        let content = UNMutableNotificationContent()
        content.title = "Спасибо!"
        content.body = "Твой чек-ин сохранён 💚"
        content.threadIdentifier = sessionID.uuidString
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)\(sessionID.uuidString).thanks.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
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
        let prefix = "\(identifierPrefix)\(sessionID.uuidString).checkin."
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
