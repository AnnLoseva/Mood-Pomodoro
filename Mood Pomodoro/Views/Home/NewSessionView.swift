//
//  NewSessionView.swift
//  Mood Pomodoro
//

import SwiftUI

struct NewSessionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var sessionType: SessionType?
    @State private var activity: String = ""
    @State private var intervalMinutes: Int = 10
    @State private var selectedConditions: [FactorCategory: FactorOption] = [:]
    @State private var showConditionsPicker = false
    @State private var showQuickCheckIn = false
    /// Off by default: almost every session starts when the button is
    /// pressed, and the picker shouldn't be in the way of the common case.
    @State private var startedEarlier = false
    @State private var startMoment: Date = .now
    @FocusState private var activityFieldFocused: Bool

    /// How far back a still-running session may be backdated. Long enough
    /// for a morning that went unrecorded, short enough that a mis-set
    /// picker can't invent a session from yesterday.
    private static let longestBackdate: TimeInterval = 12 * 60 * 60

    #if DEBUG
    private let intervalOptions = [1, 5, 10, 15, 20, 30]
    #else
    private let intervalOptions = [5, 10, 15, 20, 30]
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    MoodImage(mood: .veryGood, size: 84)
                    Text(L("Новая сессия", "New session"))
                        .font(.lora(26, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Чем занимаешься?", "What are you working on?"))
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        TextField(L("Например, Математика", "For example, Math"), text: $activity)
                            .font(.lora(17))
                            .foregroundStyle(AppTheme.ink)
                            .focused($activityFieldFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.chipFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1.25)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Или выбери из леса", "Or pick from the forest"))
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        CategoryPicker(selectedLabel: trimmedActivity) { category in
                            activity = category.label
                            activityFieldFocused = false
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Как часто спрашивать?", "How often should I ask?"))
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        IntervalPicker(options: intervalOptions, selection: $intervalMinutes)
                        #if DEBUG
                        if intervalMinutes == 1 {
                            Text(L("1 минута только для проверки уведомлений — в обычном режиме по умолчанию 10 минут.", "1 minute is only for testing notifications — normally the default is 10 minutes."))
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        #endif
                    }

                    SessionTypePicker(selection: $sessionType, showsHint: false)
                    startTimeSection

                    ConditionsSummaryView(
                        title: L("Условия", "Conditions"),
                        chips: selectedConditions.map { ConditionChip(category: $0.key, option: $0.value) }
                            .sorted { $0.name < $1.name },
                        actionTitle: selectedConditions.isEmpty ? L("+ Добавить условие", "+ Add condition") : L("Изменить условия", "Change conditions"),
                        onTap: { showConditionsPicker = true }
                    )
                }

                Button {
                    activityFieldFocused = false
                    sessionManager.startSession(
                        activity: trimmedActivity,
                        intervalMinutes: intervalMinutes,
                        startDate: resolvedStart,
                        type: sessionType,
                        initialConditions: selectedConditions
                    )
                    startedEarlier = false
                } label: {
                    Text(startedEarlier
                         ? L("Начать сессию с \(DateFormatting.time(resolvedStart))", "Start session from \(DateFormatting.time(resolvedStart))")
                         : L("Начать сессию", "Start session"))
                }
                .buttonStyle(.goblinPrimary)
                .disabled(trimmedActivity.isEmpty || sessionType == nil)
                .opacity(trimmedActivity.isEmpty ? 0.5 : 1)

                // Recording a mood shouldn't require committing to a session.
                VStack(spacing: 6) {
                    Button(L("Как я сейчас?", "How am I feeling?")) {
                        activityFieldFocused = false
                        showQuickCheckIn = true
                    }
                    .buttonStyle(.goblinSecondary)
                    Text(L("Можно просто отметить состояние — без сессии.", "You can just log your mood — no session needed."))
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            }
            .parchmentCard(padding: 24)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showConditionsPicker) {
            ConditionsPickerSheet(selection: $selectedConditions)
        }
        .sheet(isPresented: $showQuickCheckIn) {
            QuickCheckInSheet(sessionID: nil)
        }
    }

    private var trimmedActivity: String {
        activity.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - When it started

    /// For a session already under way: the work began earlier, so the
    /// elapsed time, the check-in schedule and the day chart all have to
    /// count from then rather than from the moment the button is pressed.
    private var startTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Когда началось?", "When did it start?"))
                .font(.lora(14, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
            HStack(spacing: 8) {
                startChoice(L("Сейчас", "Now"), isSelected: !startedEarlier) {
                    startedEarlier = false
                }
                startChoice(L("Уже идёт", "Already going"), isSelected: startedEarlier) {
                    // Somewhere useful to start from, rather than "now",
                    // which would mean the same as the other choice.
                    if !startedEarlier { startMoment = .now.addingTimeInterval(-30 * 60) }
                    startedEarlier = true
                    activityFieldFocused = false
                }
            }
            if startedEarlier {
                DatePicker(
                    L("Начало", "Start"),
                    selection: $startMoment,
                    in: Date.now.addingTimeInterval(-Self.longestBackdate)...Date.now,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.compact)
                .font(.lora(15))
                .tint(AppTheme.forest)
                Text(L("Идёт уже \(DurationFormatting.compact(elapsedSoFar))", "Going for \(DurationFormatting.compact(elapsedSoFar)) already"))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    private var resolvedStart: Date {
        guard startedEarlier else { return .now }
        return min(max(startMoment, .now.addingTimeInterval(-Self.longestBackdate)), .now)
    }

    private var elapsedSoFar: TimeInterval {
        Date.now.timeIntervalSince(resolvedStart)
    }

    private func startChoice(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.lora(14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                .lineLimit(1)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? AppTheme.forest : AppTheme.chipFill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryPicker: View {
    let selectedLabel: String
    let onSelect: (ActivityCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ActivityCategory.allCases) { category in
                    let isSelected = category.label == canonicalData(selectedLabel)
                    Button {
                        onSelect(category)
                    } label: {
                        VStack(spacing: 6) {
                            Image(category.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? AppTheme.forest : .clear, lineWidth: 2.5)
                                )
                            Text(category.displayLabel)
                                .font(.lora(11, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.forest : AppTheme.inkSoft)
                                // Names run from "Лего" to "Электроника на
                                // макете"; a fixed width keeps every tile the
                                // same size instead of one stretching the row.
                                .multilineTextAlignment(.center)
                                .lineLimit(2, reservesSpace: true)
                                .frame(width: 76)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct IntervalPicker: View {
    let options: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { minutes in
                let isSelected = minutes == selection
                Button {
                    selection = minutes
                } label: {
                    Text(L("\(minutes) мин", "\(minutes) min"))
                        .font(.lora(14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                        // Six chips share one row; keep "30 min" on one line.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AppTheme.forest : AppTheme.chipFill)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
