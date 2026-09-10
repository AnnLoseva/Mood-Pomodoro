//
//  TimelineRow.swift
//  Mood Pomodoro
//

import SwiftUI

struct TimelineEntry: Identifiable {
    let id: UUID
    let time: Date
    let text: String?
    let mood: Mood?
}

extension FocusSession {
    var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = [TimelineEntry(id: UUID(), time: startDate, text: "Начало", mood: nil)]
        for checkIn in sortedCheckIns {
            entries.append(TimelineEntry(id: checkIn.id, time: checkIn.timestamp, text: checkIn.reason, mood: checkIn.mood))
        }
        if let endDate {
            entries.append(TimelineEntry(id: UUID(), time: endDate, text: "Конец", mood: nil))
        }
        return entries
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.time, format: .dateTime.hour().minute())
                .font(.lora(14).monospacedDigit())
                .foregroundStyle(AppTheme.inkSoft)
                .frame(width: 52, alignment: .leading)
            if let mood = entry.mood {
                MoodImage(mood: mood, size: 30)
            }
            if let text = entry.text, !text.isEmpty {
                Text(text)
                    .font(.lora(15))
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }
}
