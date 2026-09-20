//
//  AnalyticsRoute.swift
//  Mood Pomodoro
//
//  Where the analytics can take you. One value type for every screen that
//  opens "on request", so the main screen, the search and the diary all reach
//  the same places the same way — and a route survives being handed from one
//  tab to another (`AppTabs.pendingAnalyticsRoute`).
//

import Foundation

/// The categories behind "Исследовать данные".
enum AnalyticsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case state, sleep, activities, food, emotions, factors, cycle, compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .state: return L("Состояние", "State")
        case .sleep: return L("Сон", "Sleep")
        case .activities: return L("Занятия", "Activities")
        case .food: return L("Питание", "Food")
        case .emotions: return L("Эмоции и импульсы", "Emotions & impulses")
        case .factors: return L("Факторы", "Factors")
        case .cycle: return L("Цикл и препараты", "Cycle & medication")
        case .compare: return L("Сравнение", "Compare")
        }
    }

    var symbol: String {
        switch self {
        case .state: return "face.smiling"
        case .sleep: return "moon.zzz"
        case .activities: return "leaf"
        case .food: return "fork.knife"
        case .emotions: return "sparkles"
        case .factors: return "cup.and.saucer"
        case .cycle: return "calendar"
        case .compare: return "chart.xyaxis.line"
        }
    }

    /// Words that should find this section besides its title.
    var keywords: [String] {
        switch self {
        case .state: return ["настроение", "энергия", "мотивация", "check-in", "чекин", "отметка", "причины", "mood", "energy", "motivation", "reasons", "state"]
        case .sleep: return ["ночь", "засыпание", "пробуждение", "качество сна", "стадии", "дневной сон", "sleep", "nap", "night", "bedtime", "quality", "stages"]
        case .activities: return ["сессии", "занятие", "работа", "учёба", "отдых", "фокус", "помодоро", "sessions", "activities", "activity", "work", "study", "rest", "focus"]
        case .food: return ["еда", "питание", "голод", "аппетит", "сытость", "насыщение", "hunger", "appetite", "meal", "food", "satiety"]
        case .emotions: return ["эмоции", "импульсы", "импульсивность", "чувства", "emotions", "impulses", "feelings"]
        case .factors: return ["факторы", "условия", "состояния", "conditions", "factors"]
        case .cycle: return ["цикл", "менструация", "препараты", "таблетки", "поддержка", "лекарства", "cycle", "period", "medication", "support", "pills"]
        case .compare: return ["сравнение", "сравнить", "корреляция", "compare", "versus"]
        }
    }
}

enum AnalyticsRoute: Hashable, Sendable {
    case section(AnalyticsSection)
    case metric(AnalyticsMetric)
    /// One activity by its canonical name (`canonicalData`).
    case activity(String)
    case factorCategory(UUID)
    /// Everything recorded on one day, each record openable.
    case day(Date)
    case session(UUID)
    /// Finished sessions in the chosen period; `activity` narrows it.
    case sessions(activity: String?)
    /// The nights behind a sleep aggregate.
    case nights
    /// The raw records of one kind in the chosen period.
    case records(AnalyticsRecordKind)
    case search
}

/// Kinds of raw record the analytics can list, so an aggregate (meals,
/// emotions, impulses, cycle marks, medication days) always has a way to the
/// entries it counted.
enum AnalyticsRecordKind: String, Hashable, Sendable, CaseIterable {
    case meals, hunger, emotions, impulses, cycle, medication

    var title: String {
        switch self {
        case .meals: return L("Приёмы пищи", "Meals")
        case .hunger: return L("Голод и аппетит", "Hunger & appetite")
        case .emotions: return L("Эмоции", "Emotions")
        case .impulses: return L("Импульсы", "Impulses")
        case .cycle: return L("Отметки цикла", "Cycle marks")
        case .medication: return L("Препараты", "Medication")
        }
    }
}
