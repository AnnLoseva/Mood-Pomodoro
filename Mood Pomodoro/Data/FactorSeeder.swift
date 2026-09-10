//
//  FactorSeeder.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// Seeds the starter set of condition categories/options on first launch.
/// Runs once — if any `FactorCategory` already exists, it's a no-op, so
/// user edits (renames, disables, new categories) are never overwritten.
enum FactorSeeder {
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<FactorCategory>())) ?? 0
        guard existing == 0 else { return }

        for (index, spec) in defaultCategories.enumerated() {
            let category = FactorCategory(
                name: spec.name,
                icon: spec.icon,
                iconImageName: spec.iconImageName,
                sortOrder: index
            )
            context.insert(category)
            for (optionIndex, option) in spec.options.enumerated() {
                let factorOption = FactorOption(
                    name: option.name,
                    icon: spec.icon,
                    iconImageName: option.iconImageName,
                    sortOrder: optionIndex
                )
                factorOption.category = category
                category.options.append(factorOption)
                context.insert(factorOption)
            }
        }
        try? context.save()
    }

    private struct OptionSpec {
        let name: String
        /// Only set when this specific option has its own artwork (e.g. each
        /// drink); otherwise it falls back to the category's image.
        var iconImageName: String? = nil
    }

    private struct CategorySpec {
        let name: String
        let icon: String
        let iconImageName: String?
        let options: [OptionSpec]
    }

    private static let defaultCategories: [CategorySpec] = [
        CategorySpec(name: "Музыка", icon: "🎧", iconImageName: "FactorMusic", options: [
            OptionSpec(name: "Без музыки"),
            OptionSpec(name: "Фоновая музыка"),
            OptionSpec(name: "Lo-fi"),
            OptionSpec(name: "Саундтрек / OST"),
            OptionSpec(name: "Другое")
        ]),
        CategorySpec(name: "Напиток", icon: "☕", iconImageName: "FactorCoffee", options: [
            OptionSpec(name: "Ничего"),
            OptionSpec(name: "Кофе", iconImageName: "FactorCoffee"),
            OptionSpec(name: "Пуэр", iconImageName: "FactorPuerh"),
            OptionSpec(name: "Мате", iconImageName: "FactorMate"),
            OptionSpec(name: "Чай", iconImageName: "FactorTea"),
            OptionSpec(name: "Другое")
        ]),
        CategorySpec(name: "Поддержка", icon: "💊", iconImageName: "FactorMeds", options: [
            OptionSpec(name: "Без неё"),
            OptionSpec(name: "Лекарство"),
            OptionSpec(name: "Другое")
        ]),
        CategorySpec(name: "Сон", icon: "🌙", iconImageName: "FactorSleep", options: [
            OptionSpec(name: "Хорошо выспалась"),
            OptionSpec(name: "Нормально"),
            OptionSpec(name: "Недосып"),
            OptionSpec(name: "Очень мало сна")
        ]),
        CategorySpec(name: "Цикл", icon: "🌸", iconImageName: "FactorCycle", options: [
            OptionSpec(name: "Не отслеживать"),
            OptionSpec(name: "Фаза 1"),
            OptionSpec(name: "Фаза 2"),
            OptionSpec(name: "Фаза 3"),
            OptionSpec(name: "Фаза 4")
        ]),
        CategorySpec(name: "Место", icon: "🏠", iconImageName: "FactorPlace", options: [
            OptionSpec(name: "Дома"),
            OptionSpec(name: "Учёба"),
            OptionSpec(name: "Кафе"),
            OptionSpec(name: "На улице"),
            OptionSpec(name: "Другое")
        ]),
        CategorySpec(name: "Шум", icon: "🔊", iconImageName: "FactorNoise", options: [
            OptionSpec(name: "Тишина"),
            OptionSpec(name: "Низкий шум"),
            OptionSpec(name: "Шумно")
        ]),
        CategorySpec(name: "Люди", icon: "👥", iconImageName: "FactorPeople", options: [
            OptionSpec(name: "Одна"),
            OptionSpec(name: "С кем-то"),
            OptionSpec(name: "Группа"),
            OptionSpec(name: "Созвон")
        ]),
        CategorySpec(name: "Еда", icon: "🍽", iconImageName: "FactorFood", options: [
            OptionSpec(name: "Голодна"),
            OptionSpec(name: "Нормально"),
            OptionSpec(name: "Только поела")
        ]),
        CategorySpec(name: "Вода", icon: "💧", iconImageName: "FactorWater", options: [
            OptionSpec(name: "Не пила"),
            OptionSpec(name: "Немного"),
            OptionSpec(name: "Достаточно")
        ]),
        CategorySpec(name: "Время суток", icon: "☀️", iconImageName: "FactorTimeOfDay", options: [
            OptionSpec(name: "Утро"),
            OptionSpec(name: "День"),
            OptionSpec(name: "Вечер"),
            OptionSpec(name: "Ночь")
        ]),
        CategorySpec(name: "Рабочая обстановка", icon: "💻", iconImageName: "FactorWorkEnv", options: [
            OptionSpec(name: "Комфортно"),
            OptionSpec(name: "Отвлекают"),
            OptionSpec(name: "Неудобно")
        ]),
        CategorySpec(name: "Интерес к теме", icon: "💡", iconImageName: "FactorInterest", options: [
            OptionSpec(name: "Очень интересно"),
            OptionSpec(name: "Интересно"),
            OptionSpec(name: "Нейтрально"),
            OptionSpec(name: "Не интересно")
        ]),
        CategorySpec(name: "Степень сложности", icon: "📊", iconImageName: "FactorDifficulty", options: [
            OptionSpec(name: "Легко"),
            OptionSpec(name: "Средне"),
            OptionSpec(name: "Сложно"),
            OptionSpec(name: "Очень сложно")
        ]),
        CategorySpec(name: "Цель / мотивация", icon: "🎯", iconImageName: "FactorGoal", options: [
            OptionSpec(name: "Чёткая цель"),
            OptionSpec(name: "Смутная цель"),
            OptionSpec(name: "Без цели")
        ]),
        CategorySpec(name: "Эмоциональное состояние", icon: "🐈", iconImageName: "FactorEmotion", options: [
            OptionSpec(name: "Спокойно"),
            OptionSpec(name: "Тревожно"),
            OptionSpec(name: "Раздражена"),
            OptionSpec(name: "Вдохновлена")
        ]),
        CategorySpec(name: "Физическая активность", icon: "🏋️", iconImageName: "FactorActivityLevel", options: [
            OptionSpec(name: "Не двигалась"),
            OptionSpec(name: "Немного размялась"),
            OptionSpec(name: "Была активна")
        ])
    ]
}
