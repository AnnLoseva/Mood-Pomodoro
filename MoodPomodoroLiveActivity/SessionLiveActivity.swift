//
//  SessionLiveActivity.swift
//  MoodPomodoroLiveActivity
//
//  Lock Screen + Dynamic Island UI for an in-flight session. Timers tick
//  from timestamps via `Text(timerInterval:)` — the app never pushes
//  per-second updates.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenLiveActivityView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("🍄")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.activityName)
                            .font(.headline)
                            .lineLimit(1)
                        WorkTimerText(range: context.state.workTimerRange)
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityControls(
                        sessionID: context.attributes.sessionID,
                        state: context.state,
                        language: context.attributes.language
                    )
                }
            } compactLeading: {
                Text("🍄")
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "moon.fill")
                } else {
                    WorkTimerText(range: context.state.workTimerRange)
                        .monospacedDigit()
                        .font(.caption.weight(.semibold))
                }
            } minimal: {
                Text("🍄")
            }
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("🍄 \(attributes.activityName)")
                    .font(.headline)
                    .foregroundStyle(paletteInk)
                    .lineLimit(1)
                Spacer()
                statusLabel
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                WorkTimerText(range: state.workTimerRange)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(paletteInk)

                if let breakRange = state.breakTimerRange {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Перерыв", "Break", in: attributes.language))
                            .font(.caption)
                            .foregroundStyle(paletteInk.opacity(0.7))
                        WorkTimerText(range: breakRange)
                            .font(.title3.monospacedDigit().weight(.medium))
                            .foregroundStyle(paletteInk)
                    }
                }
            }

            if state.isPaused {
                Text(L("Ты можешь спокойно отдохнуть.", "Take your time and rest.", in: attributes.language))
                    .font(.caption)
                    .foregroundStyle(paletteInk.opacity(0.75))
            }

            LiveActivityControls(sessionID: attributes.sessionID, state: state, language: attributes.language)
        }
        .padding(16)
        .activityBackgroundTint(Color(red: 0.965, green: 0.937, blue: 0.867))
        .activitySystemActionForegroundColor(Color(red: 0.310, green: 0.400, blue: 0.271))
    }

    @ViewBuilder
    private var statusLabel: some View {
        if state.isPaused {
            Text(L("🌙 Перерыв", "🌙 Break", in: attributes.language))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(red: 0.518, green: 0.271, blue: 0.145))
        } else {
            Text(L("🟢 Работа", "🟢 Working", in: attributes.language))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(red: 0.310, green: 0.400, blue: 0.271))
        }
    }
}

private struct LiveActivityControls: View {
    let sessionID: UUID
    let state: SessionActivityAttributes.ContentState
    let language: AppLanguage

    var body: some View {
        if state.isPaused {
            HStack(spacing: 8) {
                Button(intent: ResumeSessionIntent(sessionID: sessionID)) {
                    Label(L("Продолжить", "Resume", in: language), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                Button(intent: EndSessionIntent(sessionID: sessionID)) {
                    Label(L("Закончить", "Finish", in: language), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .tint(Color(red: 0.310, green: 0.400, blue: 0.271))
        } else {
            HStack(spacing: 8) {
                Button(intent: OpenCheckInIntent(sessionID: sessionID)) {
                    Text(L("Как я сейчас", "Check in", in: language))
                        .frame(maxWidth: .infinity)
                }
                Button(intent: PauseSessionIntent(sessionID: sessionID)) {
                    Text(L("Пауза", "Pause", in: language))
                        .frame(maxWidth: .infinity)
                }
                Button(intent: EndSessionIntent(sessionID: sessionID)) {
                    Text(L("Закончить", "Finish", in: language))
                        .frame(maxWidth: .infinity)
                }
            }
            .tint(Color(red: 0.310, green: 0.400, blue: 0.271))
        }
    }
}

private struct WorkTimerText: View {
    let range: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: range, countsDown: false)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private let paletteInk = Color(red: 0.290, green: 0.220, blue: 0.149)

private extension SessionActivityAttributes {
    var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .ru }
}
