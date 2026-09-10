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
    private static let identifierPrefix = "session_"
    private static let maxScheduledPerBatch = 12
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

    /// Registers native `UNNotificationAction` buttons — these are the
    /// system's action buttons, not body text.
    ///
    /// Official iOS limits (UNNotificationCategory, 2026):
    /// - unlimited space (long-press / expanded long-look): up to 10 actions
    /// - limited space (collapsed banner): at most 2 actions
    /// There is no public API to force a 5-button grid on the collapsed banner,
    /// or to swap a delivered notification's buttons in place. Five mood
    /// actions are registered; they appear after the user expands the
    /// notification. Stage 2 (reasons) is a follow-up notification with its
    /// own category. Actions use empty options so they run in the background
    /// and do **not** open the app.
    static func registerCategories(reasons: [Mood: [String]]) {
        let moodActions = Mood.orderedCases.map { mood in
            UNNotificationAction(
                identifier: actionIdentifier(for: mood),
                title: "\(mood.emoji) \(mood.label)",
                options: [],
                icon: UNNotificationActionIcon(systemImageName: mood.notificationIconName)
            )
        }
        let checkInCategory = UNNotificationCategory(
            identifier: self.checkInCategory,
            actions: moodActions,
            intentIdentifiers: [],
            options: []
        )

        let reasonCategories = Mood.orderedCases.map { mood -> UNNotificationCategory in
            let texts = reasons[mood] ?? mood.defaultReasons
            let actions = texts.enumerated().map { index, reason in
                UNNotificationAction(
                    identifier: reasonActionIdentifier(mood: mood, index: index),
                    title: reason,
                    options: []
                )
            }
            return UNNotificationCategory(
                identifier: reasonCategory(for: mood),
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
        }

        UNUserNotificationCenter.current().setNotificationCategories(Set([checkInCategory] + reasonCategories))
    }

    static func reasonCategory(for mood: Mood) -> String { "\(reasonCategoryPrefix)\(mood.notificationActionID)" }

    static func actionIdentifier(for mood: Mood) -> String { "mood.\(mood.notificationActionID)" }

    static func mood(fromActionIdentifier identifier: String) -> Mood? {
        guard identifier.hasPrefix("mood.") else { return nil }
        return Mood.fromNotificationActionID(String(identifier.dropFirst("mood.".count)))
    }

    static func reasonActionIdentifier(mood: Mood, index: Int) -> String {
        "reason.\(mood.notificationActionID).\(index)"
    }

    /// Parses `reason.<moodActionID>.<index>` (mood IDs contain underscores).
    static func parseReasonAction(_ identifier: String) -> (mood: Mood, index: Int)? {
        guard identifier.hasPrefix("reason.") else { return nil }
        let rest = identifier.dropFirst("reason.".count)
        guard let dot = rest.lastIndex(of: ".") else { return nil }
        let moodID = String(rest[..<dot])
        let indexString = String(rest[rest.index(after: dot)...])
        guard let mood = Mood.fromNotificationActionID(moodID), let index = Int(indexString) else { return nil }
        return (mood, index)
    }

    private static func identifier(sessionID: UUID, fireDate: Date) -> String {
        "\(identifierPrefix)\(sessionID.uuidString)_checkin_\(Int(fireDate.timeIntervalSince1970))"
    }

    /// Stable across devices for one scheduled ping. iPhone and iPad both
    /// fire a local notification at 10:10; answering either writes the same
    /// occurrence so CloudKit does not keep two CheckIns.
    static func occurrenceID(sessionID: UUID, scheduledTimestamp: TimeInterval) -> String {
        "\(sessionID.uuidString)|\(Int(scheduledTimestamp))"
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

            let requestIdentifier = identifier(sessionID: session.id, fireDate: fireDate)
            let content = moodCheckInContent(
                sessionID: session.id,
                checkpoint: checkpoint,
                scheduledTimestamp: fireDate.timeIntervalSince1970
            )

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: requestIdentifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    /// Sequential stage 2. iOS cannot replace a delivered notification's
    /// action buttons in place, so a new local notification of the matching
    /// reason category is the official two-step flow. Actions are the reason
    /// texts; the body is not a fake button list.
    static func scheduleReasonPrompt(sessionID: UUID, checkInID: UUID, mood: Mood, reasons: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = "\(mood.emoji) Почему?"
        content.body = "Выбери причину"
        content.categoryIdentifier = reasonCategory(for: mood)
        content.threadIdentifier = sessionID.uuidString
        content.sound = .default
        content.userInfo = [
            "sessionID": sessionID.uuidString,
            "checkInID": checkInID.uuidString,
            "mood": mood.rawValue,
            "notificationType": "reason",
            "reasonTexts": reasons
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: reasonRequestIdentifier(sessionID: sessionID, checkInID: checkInID),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// On-demand "Как ты?" from Live Activity [Как я сейчас] — same mood
    /// *action buttons* as a periodic reminder, still without opening the app.
    static func scheduleImmediateCheckIn(sessionID: UUID) async {
        let fireDate = Date.now
        let content = moodCheckInContent(
            sessionID: sessionID,
            checkpoint: 0,
            scheduledTimestamp: fireDate.timeIntervalSince1970
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)\(sessionID.uuidString)_checkin_\(Int(fireDate.timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Title + category with 5 `UNNotificationAction` buttons. Body is a
    /// short prompt — never a row of emojis pretending to be buttons.
    private static func moodCheckInContent(
        sessionID: UUID,
        checkpoint: Int,
        scheduledTimestamp: TimeInterval
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Как ты?"
        content.body = "Нажми, чтобы ответить"
        content.categoryIdentifier = checkInCategory
        content.threadIdentifier = sessionID.uuidString
        content.sound = .default
        content.userInfo = [
            "sessionID": sessionID.uuidString,
            "checkpoint": checkpoint,
            "notificationType": "checkin",
            "scheduledTimestamp": scheduledTimestamp,
            "occurrenceID": occurrenceID(sessionID: sessionID, scheduledTimestamp: scheduledTimestamp)
        ]
        return content
    }

    static func reasonRequestIdentifier(sessionID: UUID, checkInID: UUID) -> String {
        "\(identifierPrefix)\(sessionID.uuidString)_reason_\(checkInID.uuidString)"
    }

    static func removeDelivered(identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    static func cancelAll(for sessionID: UUID) {
        let center = UNUserNotificationCenter.current()
        let prefix = "\(identifierPrefix)\(sessionID.uuidString)_"
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.getDeliveredNotifications { notifications in
            let ids = notifications.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: ids)
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
        let prefix = "\(identifierPrefix)\(sessionID.uuidString)_checkin_"
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix(prefix) }
    }

    private static func nextCheckpointIndex(existing: [UNNotificationRequest], sessionID _: UUID) -> Int {
        let checkpoints = existing.compactMap { $0.content.userInfo["checkpoint"] as? Int }
        return (checkpoints.max() ?? 0) + 1
    }
}
