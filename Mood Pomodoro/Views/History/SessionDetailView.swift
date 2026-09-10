//
//  SessionDetailView.swift
//  Mood Pomodoro
//

import SwiftUI

struct SessionDetailView: View {
    let session: FocusSession

    var body: some View {
        ZStack {
            ForestBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.timelineEntries) { entry in
                        TimelineRow(entry: entry)
                    }
                }
                .padding(20)
                .parchmentCard()
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.activity)
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }
}
