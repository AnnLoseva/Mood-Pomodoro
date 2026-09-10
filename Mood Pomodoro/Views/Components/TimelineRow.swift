//
//  TimelineRow.swift
//  Mood Pomodoro
//

import SwiftUI

/// Presentation-only timeline. Built from Session + Segments + CheckIns +
/// ConditionEvents — not a persisted model. Sorted by `timestamp`.
enum TimelineEventKind: String {
    case start
    case checkIn
    case pause
    case resume
    case conditionChanged
    case end
}

struct TimelineEvent: Identifiable {
    let id: String
    let timestamp: Date
    let kind: TimelineEventKind
    let title: String
    let subtitle: String?
    let mood: Mood?
}

extension FocusSession {
    var timelineEvents: [TimelineEvent] {
        var events: [TimelineEvent] = []

        let initialConditions = activeConditions(asOf: startDate)
        let startSubtitle = initialConditions
            .map { "\($0.categoryIcon) \($0.optionName)" }
            .joined(separator: " · ")
        events.append(
            TimelineEvent(
                id: "start-\(id.uuidString)",
                timestamp: startDate,
                kind: .start,
                title: "Начало",
                subtitle: startSubtitle.isEmpty ? nil : startSubtitle,
                mood: nil
            )
        )

        for checkIn in sortedCheckIns {
            events.append(
                TimelineEvent(
                    id: "checkin-\(checkIn.id.uuidString)",
                    timestamp: checkIn.timestamp,
                    kind: .checkIn,
                    title: checkIn.reason ?? checkIn.mood.label,
                    subtitle: nil,
                    mood: checkIn.mood
                )
            )
        }

        for segment in sortedSegments where segment.type == .pause {
            events.append(
                TimelineEvent(
                    id: "pause-\(segment.id.uuidString)",
                    timestamp: segment.startDate,
                    kind: .pause,
                    title: "Перерыв",
                    subtitle: nil,
                    mood: nil
                )
            )
            if let resumeDate = segment.endDate {
                events.append(
                    TimelineEvent(
                        id: "resume-\(segment.id.uuidString)",
                        timestamp: resumeDate,
                        kind: .resume,
                        title: "Продолжение",
                        subtitle: nil,
                        mood: nil
                    )
                )
            }
        }

        for event in sortedConditionEvents {
            // Initial conditions are already on the start row.
            if abs(event.timestamp.timeIntervalSince(startDate)) < 1 { continue }
            events.append(
                TimelineEvent(
                    id: "condition-\(event.id.uuidString)",
                    timestamp: event.timestamp,
                    kind: .conditionChanged,
                    title: "\(event.categoryIcon) \(event.categoryName) изменён: \(event.optionName)",
                    subtitle: nil,
                    mood: nil
                )
            )
        }

        if let endDate {
            events.append(
                TimelineEvent(
                    id: "end-\(id.uuidString)",
                    timestamp: endDate,
                    kind: .end,
                    title: "Завершение",
                    subtitle: nil,
                    mood: nil
                )
            )
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Kept for call sites that still use the old name.
    var timelineEntries: [TimelineEvent] { timelineEvents }
}

struct TimelineRow: View {
    let event: TimelineEvent
    /// When false, the date is shown above the time (cross-day sessions).
    var showsDate: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                if showsDate {
                    Text(DateFormatting.compactDate(event.timestamp))
                        .font(.lora(10))
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Text(DateFormatting.time(event.timestamp))
                    .font(.lora(14).monospacedDigit())
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .frame(width: showsDate ? 64 : 52, alignment: .leading)

            icon
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.lora(15))
                    .foregroundStyle(AppTheme.ink)
                if let subtitle = event.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let mood = event.mood {
            MoodImage(mood: mood, size: 28)
        } else {
            Text(kindGlyph)
                .font(.system(size: 16))
        }
    }

    private var kindGlyph: String {
        switch event.kind {
        case .start: return "▶️"
        case .checkIn: return "💬"
        case .pause: return "🌿"
        case .resume: return "▶️"
        case .conditionChanged: return "•"
        case .end: return "⏹"
        }
    }
}
