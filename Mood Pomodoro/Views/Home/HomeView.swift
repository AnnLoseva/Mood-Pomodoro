//
//  HomeView.swift
//  Mood Pomodoro
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        NavigationStack {
            Group {
                if let session = sessionManager.activeSession {
                    ActiveSessionView(session: session)
                } else {
                    NewSessionView()
                }
            }
            .navigationTitle("Mood Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
