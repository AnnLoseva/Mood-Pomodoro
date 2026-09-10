//
//  NotificationDelegate.swift
//  Mood Pomodoro
//

import Foundation
import UserNotifications
import SwiftData

/// Handles the zero-open check-in chain inside the *system* notification UI:
///  1. Mood action on "Как ты?" writes a CheckIn (reason = nil) in the
///     background — does not open the app.
///  2. The original notification is dismissed and a follow-up "🥲 Почему?"
///     is delivered immediately with data-driven reason actions.
///  3. A reason action fills in that CheckIn and a short "Спасибо!" confirms.
///
/// iOS cannot swap a delivered notification's action buttons in place, so
/// step 2 is a sequential local notification (official API), not a custom
/// in-notification screen. Tapping the notification *body* (not an action)
/// is the OS default and opens the in-app sheet as fallback.
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
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await handle(response: response)
            completionHandler()
        }
    }

    private func handle(response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let sessionID = (userInfo["sessionID"] as? String).flatMap(UUID.init)
        let checkInID = (userInfo["checkInID"] as? String).flatMap(UUID.init)
        let pendingMood = (userInfo["mood"] as? String).flatMap { Mood(rawValue: $0) }
        // Every check-in notification action is idempotency-keyed off the
        // request identifier it came from, not off anything derived at
        // handling time — two deliveries of the exact same request (a
        // double-tap, a system redelivery) must resolve to the exact same key.
        let requestIdentifier = response.notification.request.identifier

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            onRequestQuickCheckIn?(sessionID, pendingMood, checkInID)

        case UNNotificationDismissActionIdentifier:
            break

        default:
            if let mood = NotificationScheduler.mood(fromActionIdentifier: response.actionIdentifier) {
                let scheduled = userInfo["scheduledTimestamp"] as? Double
                await handleMoodAction(
                    mood: mood,
                    sessionID: sessionID,
                    sourceIdentifier: requestIdentifier,
                    scheduledTimestamp: scheduled
                )
            } else if let (mood, index) = NotificationScheduler.parseReasonAction(response.actionIdentifier) {
                let snapshot = userInfo["reasonTexts"] as? [String]
                await handleReasonAction(
                    mood: mood,
                    index: index,
                    sessionID: sessionID,
                    checkInID: checkInID,
                    reasonTexts: snapshot
                )
            }
        }
    }

    private func handleMoodAction(
        mood: Mood,
        sessionID: UUID?,
        sourceIdentifier: String,
        scheduledTimestamp: Double?
    ) async {
        guard let sessionID, let container = modelContainer else { return }
        let context = ModelContext(container)

        // Idempotency guard (spec section 20/tests 4-5): if this exact
        // notification action already produced a check-in — a redelivered
        // response, a double-tap before iOS dismissed the banner — do not
        // create a second one.
        let existingDescriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.sourceIdentifier == sourceIdentifier })
        guard (try? context.fetchCount(existingDescriptor)) == 0 else { return }

        let occurrenceID = scheduledTimestamp.map { NotificationScheduler.occurrenceID(sessionID: sessionID, scheduledTimestamp: $0) }
        if let occurrenceID {
            let byOccurrence = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.occurrenceID == occurrenceID })
            if (try? context.fetchCount(byOccurrence)) != 0 { return }
        }

        let sessionDescriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == sessionID })
        // Only an *active* (not paused/completed/cancelled) session accepts a
        // check-in: a reminder that fired right as the user paused, or that
        // lingered from a session that has since ended, must not silently
        // resurrect tracking for it.
        guard let session = try? context.fetch(sessionDescriptor).first, session.state == .active else { return }

        let timestamp = Date.now
        let checkIn = CheckIn(
            timestamp: timestamp,
            mood: mood,
            conditionSnapshot: session.activeConditions(asOf: timestamp),
            sourceIdentifier: sourceIdentifier,
            occurrenceID: occurrenceID,
            scheduledAt: scheduledTimestamp.map { Date(timeIntervalSince1970: $0) },
            origin: occurrenceID == nil ? .manual : .scheduled
        )
        checkIn.session = session
        session.checkIns = (session.checkIns ?? []) + [checkIn]
        try? context.save()

        await NotificationScheduler.topUpIfNeeded(for: session)
        NotificationScheduler.removeDelivered(identifiers: [sourceIdentifier])
        let reasons = ReasonsStore.shared.reasons(for: mood)
        await NotificationScheduler.scheduleReasonPrompt(
            sessionID: sessionID,
            checkInID: checkIn.id,
            mood: mood,
            reasons: reasons
        )
        await LiveActivityController.update(for: session)
    }

    private func handleReasonAction(
        mood: Mood,
        index: Int,
        sessionID: UUID?,
        checkInID: UUID?,
        reasonTexts: [String]?
    ) async {
        guard let sessionID, let checkInID, let container = modelContainer else { return }
        let reasons = reasonTexts ?? ReasonsStore.shared.reasons(for: mood)
        guard reasons.indices.contains(index) else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.id == checkInID })
        guard let checkIn = try? context.fetch(descriptor).first else { return }
        if checkIn.reason != nil { return }

        checkIn.reason = reasons[index]
        try? context.save()

        NotificationScheduler.removeDelivered(identifiers: [
            NotificationScheduler.reasonRequestIdentifier(sessionID: sessionID, checkInID: checkInID)
        ])
    }
}
