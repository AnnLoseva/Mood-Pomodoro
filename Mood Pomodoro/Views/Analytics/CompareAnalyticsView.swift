//
//  CompareAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct CompareAnalyticsView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case pair = "Сравнить"
        case combination = "Комбинация"
        var id: String { rawValue }
    }

    @Query(sort: \FactorCategory.sortOrder) private var allCategories: [FactorCategory]
    @Query private var sessions: [FocusSession]

    @State private var mode: Mode = .pair

    private var categories: [FactorCategory] { allCategories.filter(\.isEnabled) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Режим", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if categories.isEmpty {
                    Text("Нет условий для сравнения")
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.inkSoft)
                } else if mode == .pair {
                    PairCompareView(categories: categories, sessions: sessions)
                } else {
                    CombinationView(categories: categories, sessions: sessions)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - Pairwise compare

private struct PairCompareView: View {
    let categories: [FactorCategory]
    let sessions: [FocusSession]

    @State private var category: FactorCategory?
    @State private var optionA: FactorOption?
    @State private var optionB: FactorOption?
    @State private var activityFilter: String?

    private var activityNames: [String] { Array(Set(sessions.map(\.activity))).sorted() }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                pickerRow(title: "Фактор") {
                    Picker("", selection: $category) {
                        Text("Выбери").tag(FactorCategory?.none)
                        ForEach(categories) { cat in
                            Text("\(cat.icon) \(cat.name)").tag(FactorCategory?.some(cat))
                        }
                    }
                }
                .onChange(of: category) { _, _ in optionA = nil; optionB = nil }

                if let category {
                    pickerRow(title: "Значение A") {
                        optionPicker(selection: $optionA, options: category.enabledOptions)
                    }
                    pickerRow(title: "Значение B") {
                        optionPicker(selection: $optionB, options: category.enabledOptions)
                    }
                }

                if activityNames.count > 1 {
                    pickerRow(title: "Активность") {
                        Picker("", selection: $activityFilter) {
                            Text("Все").tag(String?.none)
                            ForEach(activityNames, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    }
                }
            }
            .padding(18)
            .parchmentCard()

            if let category, let optionA, let optionB {
                let result = AnalyticsService.compare(
                    optionA: (category, optionA),
                    optionB: (category, optionB),
                    sessions: sessions,
                    activity: activityFilter
                )
                ComparisonResultView(result: result)
            }
        }
    }

    private func optionPicker(selection: Binding<FactorOption?>, options: [FactorOption]) -> some View {
        Picker("", selection: selection) {
            Text("Выбери").tag(FactorOption?.none)
            ForEach(options) { option in
                Text(option.name).tag(FactorOption?.some(option))
            }
        }
    }

    private func pickerRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.lora(14, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
            Spacer()
            content()
                .tint(AppTheme.forest)
        }
    }
}

private struct ComparisonResultView: View {
    let result: ComparisonResult

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                resultTile(result.optionA)
                Text("vs")
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                resultTile(result.optionB)
            }

            if result.canCompare, let diff = result.moodDifference {
                Text("Разница: \(String(format: "%+.1f", diff))")
                    .font(.lora(15, weight: .semibold))
                    .foregroundStyle(diff >= 0 ? AppTheme.forest : AppTheme.rustDeep)

                if let a = result.optionA.averageMinutesToDifficult, let b = result.optionB.averageMinutesToDifficult {
                    VStack(spacing: 4) {
                        Text("Среднее время до 🥲 / 😭")
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                        Text("\(result.optionA.optionName): \(Int(a)) мин   ·   \(result.optionB.optionName): \(Int(b)) мин")
                            .font(.lora(13, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            } else {
                Text("Недостаточно данных для сравнения")
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(18)
        .parchmentCard()
    }

    private func resultTile(_ stats: FactorOptionStatistics) -> some View {
        VStack(spacing: 4) {
            Text(stats.optionName)
                .font(.lora(15, weight: .medium))
                .foregroundStyle(AppTheme.ink)
            if let avg = stats.averageMood {
                Text(String(format: "%.1f / 5", avg))
                    .font(.lora(18, weight: .semibold))
                    .foregroundStyle(AppTheme.forest)
            } else {
                Text("—").font(.lora(18)).foregroundStyle(AppTheme.inkSoft)
            }
            Text("\(stats.checkInCount) check-ins")
                .font(.lora(11))
                .foregroundStyle(AppTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Manual combination

private struct CombinationView: View {
    let categories: [FactorCategory]
    let sessions: [FocusSession]

    @State private var selection: [FactorCategory: FactorOption] = [:]
    @State private var showPicker = false

    private var pairs: [(category: FactorCategory, option: FactorOption)] {
        selection.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                ConditionsSummaryView(
                    title: "Условия комбинации",
                    chips: selection.map { ConditionChip(category: $0.key, option: $0.value) },
                    actionTitle: selection.isEmpty ? "+ Добавить условие" : "Изменить",
                    onTap: { showPicker = true }
                )
            }
            .padding(18)
            .parchmentCard()

            if !pairs.isEmpty {
                let stats = AnalyticsService.combinationStatistics(selections: pairs, sessions: sessions)
                VStack(spacing: 8) {
                    Text(stats.optionName)
                        .font(.lora(16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    if stats.hasEnoughData, let avg = stats.averageMood {
                        Text(String(format: "%.1f / 5", avg))
                            .font(.lora(26, weight: .semibold))
                            .foregroundStyle(AppTheme.forest)
                        Text("\(stats.checkInCount) check-ins")
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                        if let minutes = stats.averageMinutesToDifficult {
                            Text("Среднее время до 🥲: \(Int(minutes)) мин")
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    } else {
                        Text("\(stats.checkInCount) check-ins — недостаточно данных")
                            .font(.lora(13))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .parchmentCard()
            }
        }
        .sheet(isPresented: $showPicker) {
            ConditionsPickerSheet(selection: $selection)
        }
    }
}
