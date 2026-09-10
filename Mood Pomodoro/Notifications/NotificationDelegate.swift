//
//  NotificationDelegate.swift
//  Mood Pomodoro
//

import Foundation
import UserNotifications
import SwiftData

/// Handles notification interactions. A tap on an emoji action writes a
/// mood-only check-in straight to SwiftData — no need to launch the UI.
/// Tapping the notification body itself opens the app to the full
/// mood → reason quick check-in flow via `onRequestQuickCheckIn`.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    var modelContainer: ModelContainer?
    var onRequestQuickCheckIn: ((UUID?) -> Void)?

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

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            onRequestQuickCheckIn?(sessionID)
        case UNNotificationDismissActionIdentifier:
            break
        default:
            guard let sessionID,
                  let container = modelContainer,
                  let mood = NotificationScheduler.mood(fromActionIdentifier: response.actionIdentifier) else { return }

            let context = ModelContext(container)
            let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == sessionID })
            guard let session = try? context.fetch(descriptor).first, session.isActive else { return }

            let checkIn = CheckIn(mood: mood)
            checkIn.session = session
            session.checkIns.append(checkIn)
            try? context.save()

            await NotificationScheduler.topUpIfNeeded(for: session)
        }
    }
}
