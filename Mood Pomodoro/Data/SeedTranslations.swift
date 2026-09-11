//
//  SeedTranslations.swift
//  Mood Pomodoro
//

import Foundation

/// English names for the app's *built-in* data: the seeded factor
/// categories/options, the default mood reasons and the quick-pick
/// activities. Those are stored in Russian (they are records, and history
/// must not fork into "Кофе" and "Coffee" after a language switch), so they
/// are translated only when displayed. Anything the user typed herself has
/// no entry here and is shown exactly as written.
enum SeedTranslations {
    nonisolated static let english: [String: String] = [
        // Factor categories
        "Музыка": "Music",
        "Напиток": "Drink",
        "Поддержка": "Support",
        "Сон": "Sleep",
        "Цикл": "Cycle",
        "Место": "Place",
        "Шум": "Noise",
        "Люди": "People",
        "Еда": "Food",
        "Вода": "Water",
        "Время суток": "Time of day",
        "Рабочая обстановка": "Work setting",
        "Интерес к теме": "Interest in the topic",
        "Степень сложности": "Difficulty",
        "Цель / мотивация": "Goal / motivation",
        "Эмоциональное состояние": "Emotional state",
        "Физическая активность": "Physical activity",

        // Factor options
        "Без музыки": "No music",
        "Фоновая музыка": "Background music",
        "Саундтрек / OST": "Soundtrack / OST",
        "Другое": "Other",
        "Ничего": "Nothing",
        "Кофе": "Coffee",
        "Пуэр": "Pu-erh",
        "Мате": "Mate",
        "Чай": "Tea",
        "Без неё": "None",
        "Лекарство": "Medication",
        "Хорошо выспалась": "Slept well",
        "Нормально": "Okay",
        "Недосып": "Short on sleep",
        "Очень мало сна": "Very little sleep",
        "Не отслеживать": "Not tracking",
        "Фаза 1": "Phase 1",
        "Фаза 2": "Phase 2",
        "Фаза 3": "Phase 3",
        "Фаза 4": "Phase 4",
        "Дома": "At home",
        "Учёба": "School / university",
        "Кафе": "Café",
        "На улице": "Outdoors",
        "Тишина": "Silence",
        "Низкий шум": "Low noise",
        "Шумно": "Noisy",
        "Одна": "Alone",
        "С кем-то": "With someone",
        "Группа": "Group",
        "Созвон": "On a call",
        "Голодна": "Hungry",
        "Только поела": "Just ate",
        "Не пила": "Didn't drink",
        "Немного": "A little",
        "Достаточно": "Enough",
        "Утро": "Morning",
        "День": "Afternoon",
        "Вечер": "Evening",
        "Ночь": "Night",
        "Комфортно": "Comfortable",
        "Отвлекают": "Distracted by others",
        "Неудобно": "Uncomfortable",
        "Очень интересно": "Very interesting",
        "Интересно": "Interesting",
        "Нейтрально": "Neutral",
        "Не интересно": "Not interesting",
        "Легко": "Easy",
        "Средне": "Medium",
        "Сложно": "Hard",
        "Очень сложно": "Very hard",
        "Чёткая цель": "Clear goal",
        "Смутная цель": "Vague goal",
        "Без цели": "No goal",
        "Спокойно": "Calm",
        "Тревожно": "Anxious",
        "Раздражена": "Irritated",
        "Вдохновлена": "Inspired",
        "Не двигалась": "Didn't move",
        "Немного размялась": "Stretched a little",
        "Была активна": "Was active",

        // Default mood reasons
        "Интересная тема": "Interesting topic",
        "Я вошла в поток": "I got into a flow",
        "Всё легко получается": "Everything comes easily",
        "Сложно, но мне нравится": "Hard, but I like it",
        "Просто хорошо себя чувствую": "I just feel good",
        "Хорошо получается": "It's going well",
        "Нравится процесс": "I enjoy the process",
        "Получается лучше, чем ожидала": "Going better than I expected",
        "Просто хорошее состояние": "Just a good state",
        "Не особо интересно, но терпимо": "Not very interesting, but bearable",
        "Не сложно": "Not hard",
        "Не легко": "Not easy",
        "Просто нейтрально": "Just neutral",
        "Устала": "Tired",
        "Уже начинает надоедать": "Starting to get tedious",
        "Понимаю, но не хочется продолжать": "I understand it, but don't want to continue",
        "Хочу закончить": "I want to stop",
        "Я достаточно устала и хочу спать": "I'm quite tired and want to sleep",
        "Меня уже тошнит от этого": "I'm sick of this",
        "Мне не интересно, но я продолжаю сидеть": "Not interested, but I keep sitting here",
        "Зачем я вообще этим занимаюсь?": "Why am I even doing this?",
        "Я вообще ничего не понимаю / слишком сложно": "I don't understand anything / it's too hard",

        // Quick-pick activities (and a common typed one)
        "Математика": "Math",
        "Электроника": "Electronics",
        "Чтение": "Reading",
        "Заметки": "Notes",
        "Код": "Code",
        "Планы": "Plans",
        "Творчество": "Creative work",
        "Программирование": "Programming"
    ]
}

/// Display form of a stored built-in name: English when the app is in
/// English and the name is one of ours; otherwise unchanged.
nonisolated func Ldata(_ text: String) -> String {
    guard AppLanguage.current == .en else { return text }
    return SeedTranslations.english[text] ?? text
}
