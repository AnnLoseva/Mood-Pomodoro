//
//  Mood_PomodoroApp.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

@main
struct Mood_PomodoroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer
    @State private var sessionManager: SessionManager
    private let reasonsStore = ReasonsStore.shared

    @State private var quickCheckInSessionID: UUID?
    @State private var quickCheckInPresetMood: Mood?
    @State private var quickCheckInExistingID: UUID?
    @State private var showQuickCheckIn = false

    init() {
        let container = PersistenceController.makeContainer()
        self.container = container
        _sessionManager = State(wrappedValue: SessionManager(container: container))
        NotificationDelegate.shared.modelContainer = container
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(reasonsStore)
                .modelContainer(container)
                .sheet(isPresented: $showQuickCheckIn) {
                    QuickCheckInSheet(
                        sessionID: quickCheckInSessionID,
                        presetMood: quickCheckInPresetMood,
                        existingCheckInID: quickCheckInExistingID
                    )
                }
                .task {
                    NotificationDelegate.shared.onRequestQuickCheckIn = { sessionID, presetMood, existingCheckInID in
                        quickCheckInSessionID = sessionID ?? sessionManager.activeSession?.id
                        quickCheckInPresetMood = presetMood
                        quickCheckInExistingID = existingCheckInID
                        showQuickCheckIn = true
                    }
                    _ = await NotificationScheduler.requestAuthorizationIfNeeded()
                    sessionManager.refresh()
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
