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

        // Retired check-in reasons: the mixed mood list from before the
        // three scales were separated. Still on records in history.
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

        // Check-in reasons — mood (emotional) and motivation (the
        // activity). The retired mixed list stays below it.
        "Просто очень хорошо": "Just really good",
        "Что-то порадовало": "Something made me happy",
        "Спокойно и приятно": "Calm and pleasant",
        "Чувствую воодушевление": "Feeling inspired",
        "Всё сейчас нравится": "I like everything right now",
        "Просто хорошее настроение": "Just in a good mood",
        "Приятно и спокойно": "Pleasant and calm",
        "Что-то подняло настроение": "Something lifted my mood",
        "Чувствую себя комфортно": "I feel comfortable",
        "Сейчас всё ок": "Everything's okay right now",
        "Ничего особенного": "Nothing special",
        "Немного хорошо, немного тяжело": "A bit good, a bit hard",
        "Просто нормально": "Just okay",
        "Что-то расстроило": "Something upset me",
        "Грустно": "Sad",
        "Сейчас эмоционально тяжело": "Emotionally hard right now",
        "Очень грустно": "Very sad",
        "Сильно тревожно": "Very anxious",
        "Очень раздражена": "Very irritated",
        "Что-то сильно задело": "Something really got to me",
        "Сейчас совсем тяжело": "Really hard right now",
        "Материал очень интересный": "The material is really interesting",
        "Поймала поток": "I caught the flow",
        "Очень хочется разобраться глубже": "I really want to dig deeper",
        "Вижу заметный прогресс": "I can see real progress",
        "Очень нравится сам процесс": "I really enjoy the process itself",
        "Тема интересная": "The topic is interesting",
        "Всё хорошо получается": "It's all going well",
        "Есть понятная цель": "I have a clear goal",
        "Хочется закончить начатое": "I want to finish what I started",
        "Сейчас приятно этим заниматься": "It's nice to be doing this right now",
        "Просто нормально идёт": "It's just going okay",
        "Материал понятный, но не цепляет": "The material is clear but doesn't grab me",
        "Делаю потому что надо": "Doing it because I have to",
        "Немного устала, но терпимо": "A bit tired, but bearable",
        "Пока не надоело": "Not fed up yet",
        "Материал слишком тяжёлый": "The material is too hard",
        "Материал скучный": "The material is boring",
        "Устала от этого занятия": "Tired of this activity",
        "Уже надоело делать одно и то же": "Fed up doing the same thing over and over",
        "Начинает раздражать": "It's starting to annoy me",
        "Ничего не понимаю и это бесит": "I don't understand any of it and it's infuriating",
        "Материал невыносимо скучный": "The material is unbearably boring",
        "Я полностью вымоталась от этого": "I'm completely worn out by this",
        "Меня уже тошнит от этого действия": "I'm sick of doing this",
        "Всё в этом сейчас раздражает": "Everything about this is irritating right now",

        // Quick-pick activities
        "Зарядка": "Exercise",
        "Купить продукты": "Groceries",
        "Уборка": "Cleaning",
        "Работа метапелет": "Metapelet work",
        "Прогулка": "Walk",
        "Просмотр сериалов": "Watching shows",
        "Видеоигры": "Video games",
        "Готовка еды": "Cooking",
        "Дневной сон": "Nap",
        "Математика": "Math",
        "Электроника на макете": "Electronics — breadboard",
        "Электроника — пайка": "Electronics — soldering",
        "Чтение": "Reading",
        "Программирование": "Programming",
        "Рисование": "Drawing",
        "Лего": "Lego",
        "Музыкальные инструменты": "Playing instruments",
        "Учёба и теория": "Studying / theory",
        "Институт — теория": "University — theory",
        "Институт — практика": "University — practice",
        "Дома — теория": "Home — theory",
        "Дома — практика": "Home — practice",
        "Геймдев": "Gamedev",
        "Писательство": "Writing",
        "3D-моделирование": "3D modeling",

        // Retired quick-picks. No longer offered, but sessions recorded
        // under them are still in history and still have to read in English.
        "Электроника": "Electronics",
        "Заметки": "Notes",
        "Код": "Code",
        "Планы": "Plans",
        "Творчество": "Creative work"
    ]

    /// English spellings that mean one of our activities but aren't the
    /// mirror image of an `english` entry — activities typed by hand in
    /// English, or under an older name. Keys are lowercased. An exact
    /// `english` pair wins over an alias, so only spellings that no pair
    /// already covers belong here.
    private nonisolated static let englishAliases: [String: String] = [
        "cleaning up": "Уборка",
        "tidying": "Уборка",
        "groceries shopping": "Купить продукты",
        "grocery shopping": "Купить продукты",
        "shopping": "Купить продукты",
        "cooking food": "Готовка еды",
        "work": "Работа метапелет",
        "walking": "Прогулка",
        "a walk": "Прогулка",
        "tv shows": "Просмотр сериалов",
        "series": "Просмотр сериалов",
        "watching series": "Просмотр сериалов",
        "gaming": "Видеоигры",
        "games": "Видеоигры",
        "video game": "Видеоигры",
        "daytime nap": "Дневной сон",
        "napping": "Дневной сон",
        "maths": "Математика",
        "mathematics": "Математика",
        "breadboard": "Электроника на макете",
        "soldering": "Электроника — пайка",
        "coding": "Программирование",
        "painting": "Рисование",
        "playing music": "Музыкальные инструменты",
        "guitar": "Музыкальные инструменты",
        "study": "Учёба и теория",
        "studying": "Учёба и теория",
        "theory": "Учёба и теория",
        "game dev": "Геймдев",
        "3d modelling": "3D-моделирование",
        "3d": "3D-моделирование"
    ]

    /// The other direction: a record typed in English ("cleaning") read back
    /// as the Russian name it belongs to ("Уборка"), so the two don't sit in
    /// analytics as two separate activities. Keys are lowercased.
    nonisolated static let russian: [String: String] = {
        var map = englishAliases
        for (ru, en) in english {
            // An `english` entry wins over an alias: it is the exact pair.
            map[en.lowercased()] = ru
        }
        return map
    }()
}

/// Display form of a stored built-in name, in whichever language the app is
/// in: "Уборка" reads as "Cleaning" in English, and a record written as
/// "cleaning" reads as "Уборка" in Russian. Anything the user typed that
/// isn't one of ours is shown exactly as written.
nonisolated func Ldata(_ text: String) -> String {
    switch AppLanguage.current {
    case .en:
        if let english = SeedTranslations.english[text] { return english }
        // Already English, but possibly an older spelling of one of ours.
        guard let russian = SeedTranslations.russian[normalizedDataKey(text)] else { return text }
        return SeedTranslations.english[russian] ?? text
    case .ru:
        return SeedTranslations.russian[normalizedDataKey(text)] ?? text
    }
}

/// The Russian name a stored one belongs to — the form history is grouped
/// by, so sessions logged as "Уборка" and as "cleaning" count as one
/// activity rather than two. Names that aren't ours are returned unchanged.
nonisolated func canonicalData(_ text: String) -> String {
    if SeedTranslations.english[text] != nil { return text }
    return SeedTranslations.russian[normalizedDataKey(text)] ?? text
}

private nonisolated func normalizedDataKey(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
