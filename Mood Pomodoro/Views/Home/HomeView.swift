//
//  HomeView.swift
//  Mood Pomodoro
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()

                Group {
                    if let session = sessionManager.activeSession {
                        ActiveSessionView(session: session)
                    } else {
                        NewSessionView()
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Mood Pomodoro")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }
}
