//
//  NewSessionView.swift
//  Mood Pomodoro
//

import SwiftUI

struct NewSessionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var activity: String = ""
    @State private var intervalMinutes: Int = 10
    @State private var selectedConditions: [FactorCategory: FactorOption] = [:]
    @State private var showConditionsPicker = false
    @State private var showQuickCheckIn = false
    @FocusState private var activityFieldFocused: Bool

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
                    Text("Новая сессия")
                        .font(.lora(26, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Чем занимаешься?")
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        TextField("Например, Математика", text: $activity)
                            .font(.lora(17))
                            .foregroundStyle(AppTheme.ink)
                            .focused($activityFieldFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.parchment.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1.25)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Или выбери из леса")
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        CategoryPicker(selectedLabel: trimmedActivity) { category in
                            activity = category.label
                            activityFieldFocused = false
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Как часто спрашивать?")
                            .font(.lora(14, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                        IntervalPicker(options: intervalOptions, selection: $intervalMinutes)
                        #if DEBUG
                        if intervalMinutes == 1 {
                            Text("1 минута только для проверки уведомлений — в обычном режиме по умолчанию 10 минут.")
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        #endif
                    }

                    ConditionsSummaryView(
                        title: "Условия",
                        chips: selectedConditions.map { ConditionChip(category: $0.key, option: $0.value) }
                            .sorted { $0.name < $1.name },
                        actionTitle: selectedConditions.isEmpty ? "+ Добавить условие" : "Изменить условия",
                        onTap: { showConditionsPicker = true }
                    )
                }

                Button {
                    activityFieldFocused = false
                    sessionManager.startSession(
                        activity: trimmedActivity,
                        intervalMinutes: intervalMinutes,
                        initialConditions: selectedConditions
                    )
                } label: {
                    Text("Начать сессию")
                }
                .buttonStyle(.goblinPrimary)
                .disabled(trimmedActivity.isEmpty)
                .opacity(trimmedActivity.isEmpty ? 0.5 : 1)

                // Recording a mood shouldn't require committing to a session.
                VStack(spacing: 6) {
                    Button("Как я сейчас?") {
                        activityFieldFocused = false
                        showQuickCheckIn = true
                    }
                    .buttonStyle(.goblinSecondary)
                    Text("Можно просто отметить состояние — без сессии.")
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
}

private struct CategoryPicker: View {
    let selectedLabel: String
    let onSelect: (ActivityCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ActivityCategory.allCases) { category in
                    let isSelected = category.label == selectedLabel
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
                            Text(category.label)
                                .font(.lora(11, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.forest : AppTheme.inkSoft)
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
                    Text("\(minutes) мин")
                        .font(.lora(14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AppTheme.forest : AppTheme.parchment.opacity(0.5))
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
