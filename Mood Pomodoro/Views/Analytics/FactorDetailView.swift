//
//  FactorDetailView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct FactorDetailView: View {
    let category: FactorCategory

    @Query private var sessions: [FocusSession]
    @State private var activityFilter: String?

    private var activityNames: [String] {
        Array(Set(sessions.map(\.activity))).sorted()
    }

    private var stats: FactorCategoryStatistics {
        AnalyticsService.factorStatistics(categories: [category], sessions: sessions, activity: activityFilter).first
            ?? FactorCategoryStatistics(id: category.id, categoryName: category.name, categoryIcon: category.icon, optionStats: [])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if activityNames.count > 1 {
                    activityFilterRow
                }

                VStack(spacing: 10) {
                    ForEach(stats.optionStats) { option in
                        optionRow(option)
                    }
                }
                .padding(18)
                .parchmentCard()

                Text("Показывает связь, не причину: среднее состояние в твоих наблюдениях, а не вывод о том, что помогает.")
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(category.icon)
                    Text(category.name).font(.lora(17, weight: .semibold)).foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    private var activityFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "Все", isSelected: activityFilter == nil) { activityFilter = nil }
                ForEach(activityNames, id: \.self) { name in
                    filterChip(title: name, isSelected: activityFilter == name) { activityFilter = name }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.lora(13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? AppTheme.forest : AppTheme.parchment.opacity(0.5)))
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func optionRow(_ option: FactorOptionStatistics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                FactorIconView(icon: option.optionIcon, iconImageName: option.optionIconImageName, size: 22)
                Text(option.optionName)
                    .font(.lora(15, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if let avg = option.averageMood {
                    Text(String(format: "%.1f / 5", avg))
                        .font(.lora(15, weight: .semibold))
                        .foregroundStyle(AppTheme.forest)
                }
            }
            if option.hasEnoughData {
                Text("\(option.checkInCount) check-ins" + (option.goodMoodShare.map { " · \(Int(($0 * 100).rounded()))% хороших" } ?? ""))
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            } else {
                Text("\(option.checkInCount) check-ins — недостаточно данных")
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
        .padding(.vertical, 4)
    }
}
