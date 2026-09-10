//
//  TimelineRow.swift
//  Mood Pomodoro
//

import SwiftUI

struct TimelineEntry: Identifiable {
    let id: UUID
    let time: Date
    let text: String?
    let emoji: String?
}

extension FocusSession {
    var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = [TimelineEntry(id: UUID(), time: startDate, text: "Start", emoji: nil)]
        for checkIn in sortedCheckIns {
            entries.append(TimelineEntry(id: checkIn.id, time: checkIn.timestamp, text: checkIn.reason, emoji: checkIn.mood.emoji))
        }
        if let endDate {
            entries.append(TimelineEntry(id: UUID(), time: endDate, text: "End", emoji: nil))
        }
        return entries
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.time, format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            if let emoji = entry.emoji {
                Text(emoji).font(.title3)
            }
            if let text = entry.text, !text.isEmpty {
                Text(text)
            }
        }
    }
}
