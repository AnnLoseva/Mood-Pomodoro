//
//  ConditionsPickerSheet.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// Two-step picker — category, then option — mirroring `QuickCheckInSheet`'s
/// mood → reason flow. Reused both for choosing conditions before a session
/// starts and for changing them mid-session; the caller owns what "save"
/// means (store locally vs. write a `ConditionEvent`).
struct ConditionsPickerSheet: View {
    @Query(sort: \FactorCategory.sortOrder) private var allCategories: [FactorCategory]
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: [FactorCategory: FactorOption]
    var onDone: () -> Void = {}

    @State private var activeCategory: FactorCategory?

    private var categories: [FactorCategory] {
        allCategories.filter(\.isEnabled)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.parchmentCard.ignoresSafeArea()

                if let category = activeCategory {
                    OptionListView(
                        category: category,
                        selected: selection[category]
                    ) { option in
                        selection[category] = option
                        activeCategory = nil
                    } onClear: {
                        selection.removeValue(forKey: category)
                        activeCategory = nil
                    }
                } else {
                    CategoryListView(categories: categories, selection: selection) { category in
                        activeCategory = category
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(activeCategory?.name ?? "Условия")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if activeCategory != nil {
                        Button {
                            activeCategory = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .foregroundStyle(AppTheme.forest)
                    } else {
                        Button("Закрыть") { dismiss() }
                            .foregroundStyle(AppTheme.forest)
                    }
                }
                if activeCategory == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") {
                            onDone()
                            dismiss()
                        }
                        .font(.lora(15, weight: .semibold))
                        .foregroundStyle(AppTheme.forest)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CategoryListView: View {
    let categories: [FactorCategory]
    let selection: [FactorCategory: FactorOption]
    let onSelect: (FactorCategory) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(categories) { category in
                    Button {
                        onSelect(category)
                    } label: {
                        HStack(spacing: 12) {
                            FactorIconView(icon: category.icon, iconImageName: category.iconImageName, size: 30)
                            Text(category.name)
                                .font(.lora(16, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            if let chosen = selection[category] {
                                Text(chosen.name)
                                    .font(.lora(14))
                                    .foregroundStyle(AppTheme.forest)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.parchment.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1.25)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

private struct OptionListView: View {
    let category: FactorCategory
    let selected: FactorOption?
    let onSelect: (FactorOption) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(category.enabledOptions) { option in
                    let isSelected = option.id == selected?.id
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(spacing: 12) {
                            FactorIconView(
                                icon: category.icon,
                                iconImageName: option.iconImageName ?? category.iconImageName,
                                size: 26
                            )
                            Text(option.name)
                                .font(.lora(16, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.parchmentCard)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AppTheme.forest : AppTheme.parchment.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1.25)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if selected != nil {
                    Button("Не указывать", role: .destructive, action: onClear)
                        .font(.lora(13))
                        .foregroundStyle(AppTheme.rustDeep)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }
}
