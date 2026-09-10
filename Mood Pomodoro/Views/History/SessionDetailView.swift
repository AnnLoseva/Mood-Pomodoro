//
//  SessionDetailView.swift
//  Mood Pomodoro
//

import SwiftUI

struct SessionDetailView: View {
    let session: FocusSession

    var body: some View {
        List(session.timelineEntries) { entry in
            TimelineRow(entry: entry)
        }
        .navigationTitle(session.activity)
        .navigationBarTitleDisplayMode(.inline)
    }
}
