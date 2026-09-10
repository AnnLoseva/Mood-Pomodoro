//
//  NotificationDelegate.swift
//  Mood Pomodoro
//

import Foundation
import UserNotifications
import SwiftData

/// Handles notification interactions for the full "Как ты?" → "Почему так?"
/// → "Спасибо!" chain — every step is answerable from the lock screen, no
/// need to open the app:
///  - A mood emoji action writes a mood-only check-in, then immediately
///    schedules the "Почему так?" follow-up for that mood.
///  - A reason action fills in that check-in's reason, then schedules the
///    "Спасибо!" confirmation.
/// Tapping a notification's body instead opens the app to the matching step
/// of `QuickCheckInSheet` via `onRequestQuickCheckIn`.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    var modelContainer: ModelContainer?
    /// (sessionID, presetMood, existingCheckInID) — presetMood/existingCheckInID
    /// are set when the tap came from a "Почему так?" notification, so the
    /// sheet can jump straight to the reason step instead of the mood picker.
    var onRequestQuickCheckIn: ((UUID?, Mood?, UUID?) -> Void)?

    private override init() { super.init() }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await handle(response: response)
    }

    private func handle(response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let sessionID = (userInfo["sessionID"] as? String).flatMap(UUID.init)
        let checkInID = (userInfo["checkInID"] as? String).flatMap(UUID.init)
        let pendingMood = (userInfo["mood"] as? String).flatMap { Mood(rawValue: $0) }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            onRequestQuickCheckIn?(sessionID, pendingMood, checkInID)

        case UNNotificationDismissActionIdentifier:
            break

        default:
            if let mood = NotificationScheduler.mood(fromActionIdentifier: response.actionIdentifier) {
                await handleMoodAction(mood: mood, sessionID: sessionID)
            } else if let (mood, index) = NotificationScheduler.parseReasonAction(response.actionIdentifier) {
                await handleReasonAction(mood: mood, index: index, sessionID: sessionID, checkInID: checkInID)
            }
        }
    }

    private func handleMoodAction(mood: Mood, sessionID: UUID?) async {
        guard let sessionID, let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == sessionID })
        guard let session = try? context.fetch(descriptor).first, session.isActive else { return }

        let checkIn = CheckIn(mood: mood)
        checkIn.session = session
        session.checkIns.append(checkIn)
        try? context.save()

        await NotificationScheduler.topUpIfNeeded(for: session)
        await NotificationScheduler.scheduleReasonPrompt(sessionID: sessionID, checkInID: checkIn.id, mood: mood)
    }

    private func handleReasonAction(mood: Mood, index: Int, sessionID: UUID?, checkInID: UUID?) async {
        guard let sessionID, let checkInID, let container = modelContainer else { return }
        let reasons = ReasonsStore.shared.reasons(for: mood)
        guard reasons.indices.contains(index) else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == checkInID })
        guard let checkIn = try? context.fetch(descriptor).first else { return }

        checkIn.reason = reasons[index]
        try? context.save()

        await NotificationScheduler.scheduleThankYou(sessionID: sessionID)
    }
}
