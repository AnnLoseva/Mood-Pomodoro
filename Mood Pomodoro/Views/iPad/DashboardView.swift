//
//  DashboardView.swift
//  Mood Pomodoro
//

import SwiftUI

/// iPad's "Сегодня" detail pane: the active session plus its timeline side
/// by side. Kept close to the phone layout on purpose — the priority stays
/// a fast check-in, not a dense dashboard.
struct DashboardView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        if let session = sessionManager.activeSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ActiveSessionView(session: session)
                        .frame(maxWidth: .infinity)

                    if !session.sortedCheckIns.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Timeline")
                                .font(.headline)
                                .padding(.horizontal)
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(session.timelineEntries) { entry in
                                    TimelineRow(entry: entry)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                        }
                        .frame(maxWidth: 600)
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
            }
        } else {
            NewSessionView()
        }
    }
}
