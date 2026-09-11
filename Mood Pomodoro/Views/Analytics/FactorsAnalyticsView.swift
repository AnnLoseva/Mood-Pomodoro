//
//  FactorsAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct FactorsAnalyticsView: View {
    @Query(sort: \FactorCategory.sortOrder) private var allCategories: [FactorCategory]

    private var categories: [FactorCategory] { allCategories.filter(\.isEnabled) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if categories.isEmpty {
                    Text(L("Нет условий", "No conditions"))
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.inkSoft)
                } else {
                    ForEach(categories) { category in
                        NavigationLink(value: category) {
                            HStack(spacing: 12) {
                                FactorIconView(icon: category.icon, iconImageName: category.iconImageName, size: 30)
                                Text(Ldata(category.name))
                                    .font(.lora(16, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.parchmentCard)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border, lineWidth: 1.25)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationDestination(for: FactorCategory.self) { category in
            FactorDetailView(category: category)
        }
    }
}
