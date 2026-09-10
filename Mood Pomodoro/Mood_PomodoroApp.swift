//
//  Mood_PomodoroApp.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct Mood_PomodoroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer
    @State private var sessionManager: SessionManager
    @State private var cycleStore: CycleStore
    @State private var diaryStore: DiaryEntryStore
    @State private var cloudSync = CloudSyncStatus()
    private let reasonsStore = ReasonsStore.shared

    @State private var quickCheckInSessionID: UUID?
    @State private var quickCheckInPresetMood: Mood?
    @State private var quickCheckInExistingID: UUID?
    @State private var showQuickCheckIn = false
    @State private var showNotificationExplainer = false

    init() {
        let container = PersistenceController.makeContainer()
        self.container = container
        let manager = SessionManager(container: container)
        _sessionManager = State(wrappedValue: manager)
        _cycleStore = State(wrappedValue: CycleStore(container: container))
        _diaryStore = State(wrappedValue: DiaryEntryStore(container: container))
        NotificationDelegate.shared.modelContainer = container
        SessionIntentRuntime.bind(manager)
        ReasonsStore.shared.bind(context: ModelContext(container))
        NotificationScheduler.registerCategories(reasons: ReasonsStore.shared.reasons)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(reasonsStore)
                .environment(cloudSync)
                .environment(cycleStore)
                .environment(diaryStore)
                .modelContainer(container)
                .sheet(isPresented: $showQuickCheckIn) {
                    QuickCheckInSheet(
                        sessionID: quickCheckInSessionID,
                        presetMood: quickCheckInPresetMood,
                        existingCheckInID: quickCheckInExistingID
                    )
                }
                .alert("Как ты?", isPresented: $showNotificationExplainer) {
                    Button("Продолжить") {
                        Task { _ = await NotificationScheduler.requestAuthorizationIfNeeded() }
                    }
                    Button("Позже", role: .cancel) {}
                } message: {
                    Text("Приложение будет иногда спрашивать «Как ты?» во время занятий. Ответ можно дать прямо из уведомления.")
                }
                .task {
                    NotificationDelegate.shared.onRequestQuickCheckIn = { sessionID, presetMood, existingCheckInID in
                        quickCheckInSessionID = sessionID ?? sessionManager.activeSession?.id
                        quickCheckInPresetMood = presetMood
                        quickCheckInExistingID = existingCheckInID
                        showQuickCheckIn = true
                    }
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .notDetermined {
                        showNotificationExplainer = true
                    }
                    sessionManager.refresh()
                    await cloudSync.refresh(usingCloudKitStore: PersistenceController.isUsingCloudKit)
                }
                .onReceive(NotificationCenter.default.publisher(for: .howAreYouRequestCheckIn)) { output in
                    let id = (output.object as? UUID) ?? sessionManager.activeSession?.id
                    quickCheckInSessionID = id
                    quickCheckInPresetMood = nil
                    quickCheckInExistingID = nil
                    showQuickCheckIn = true
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            sessionManager.refresh()
            if let session = sessionManager.activeSession {
                Task { await NotificationScheduler.topUpIfNeeded(for: session) }
            }
        }
    }

}

/// Holds the running `SessionManager` for Live Activity intents. Intents are
/// `@Sendable` and must not capture the MainActor manager from `App.init`.
enum SessionIntentRuntime {
    nonisolated(unsafe) static var manager: SessionManager?

    static func bind(_ manager: SessionManager) {
        self.manager = manager
        SessionIntentBridge.bind(
            pause: { sessionID in
                guard let id = UUID(uuidString: sessionID) else { return }
                await MainActor.run { SessionIntentRuntime.manager?.pause(sessionID: id) }
            },
            resume: { sessionID in
                guard let id = UUID(uuidString: sessionID) else { return }
                await MainActor.run { SessionIntentRuntime.manager?.resume(sessionID: id) }
            },
            end: { sessionID in
                guard let id = UUID(uuidString: sessionID) else { return }
                await MainActor.run { SessionIntentRuntime.manager?.finish(sessionID: id) }
            },
            recordMood: { sessionID, moodRaw in
                guard let id = UUID(uuidString: sessionID) else { return }
                await MainActor.run {
                    SessionIntentRuntime.manager?.recordMoodFromLiveActivity(sessionID: id, moodRaw: moodRaw)
                }
            },
            requestCheckIn: { sessionID in
                guard let id = UUID(uuidString: sessionID) else { return }
                let isActive = await MainActor.run {
                    SessionIntentRuntime.manager?.session(withID: id)?.state == .active
                }
                guard isActive else { return }
                await NotificationScheduler.scheduleImmediateCheckIn(sessionID: id)
            }
        )
    }
}

extension Notification.Name {
    static let howAreYouRequestCheckIn = Notification.Name("howAreYouRequestCheckIn")
}
