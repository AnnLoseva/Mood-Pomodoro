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
    /// Set for a condition-change entry ("🎧 Music = Lo-fi") instead of a
    /// check-in or start/end marker.
    let conditionIcon: String?
}

extension FocusSession {
    var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = [
            TimelineEntry(id: UUID(), time: startDate, text: "Начало", mood: nil, conditionIcon: nil)
        ]
        for checkIn in sortedCheckIns {
            entries.append(
                TimelineEntry(id: checkIn.id, time: checkIn.timestamp, text: checkIn.reason, mood: checkIn.mood, conditionIcon: nil)
            )
        }
        for event in sortedConditionEvents {
            entries.append(
                TimelineEntry(
                    id: event.id,
                    time: event.timestamp,
                    text: "\(event.categoryName) = \(event.optionName)",
                    mood: nil,
                    conditionIcon: event.categoryIcon
                )
            )
        }
        if let endDate {
            entries.append(TimelineEntry(id: UUID(), time: endDate, text: "Конец", mood: nil, conditionIcon: nil))
        }
        return entries.sorted { $0.time < $1.time }
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
            } else if let conditionIcon = entry.conditionIcon {
                Text(conditionIcon).font(.system(size: 18))
            }
            if let text = entry.text, !text.isEmpty {
                Text(text)
                    .font(.lora(entry.conditionIcon != nil ? 13 : 15))
                    .foregroundStyle(entry.conditionIcon != nil ? AppTheme.inkSoft : AppTheme.ink)
            }
        }
    }
}
