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
            .overlay(alignment: .topTrailing) {
                LanguageMenu()
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 8)
                    .padding(.top, 2)
            }
            .hideRootNavigationBar()
            .goblinChrome()
        }
    }
}
