//
//  ActivityCategory.swift
//  Mood Pomodoro
//

import Foundation

/// Optional quick-pick activity categories shown on the New Session screen.
/// Purely a UI convenience — picking one just fills in the free-text
/// activity field, it isn't stored as its own attribute on `FocusSession`.
///
/// The order here is the order they appear in the picker.
enum ActivityCategory: String, CaseIterable, Identifiable {
    case exercise
    case groceries
    case cleaning
    case work
    case walk
    case shows
    case videoGames
    case cooking
    case nap
    case math
    case breadboard
    case soldering
    case reading
    case programming
    case drawing
    case lego
    case music
    case study
    case gamedev
    case writing
    case modeling3D

    var id: String { rawValue }

    /// What gets stored on a session. Stays Russian so history doesn't fork
    /// by language; `SeedTranslations` carries the English form.
    var label: String {
        switch self {
        case .exercise: return "Зарядка"
        case .groceries: return "Купить продукты"
        case .cleaning: return "Уборка"
        case .work: return "Работа метапелет"
        case .walk: return "Прогулка"
        case .shows: return "Просмотр сериалов"
        case .videoGames: return "Видеоигры"
        case .cooking: return "Готовка еды"
        case .nap: return "Дневной сон"
        case .math: return "Математика"
        case .breadboard: return "Электроника на макете"
        case .soldering: return "Электроника — пайка"
        case .reading: return "Чтение"
        case .programming: return "Программирование"
        case .drawing: return "Рисование"
        case .lego: return "Лего"
        case .music: return "Музыкальные инструменты"
        case .study: return "Учёба и теория"
        case .gamedev: return "Геймдев"
        case .writing: return "Писательство"
        case .modeling3D: return "3D-моделирование"
        }
    }

    /// `label` is what gets stored on a session (it stays Russian so history
    /// doesn't fork by language); this is what's shown.
    var displayLabel: String { Ldata(label) }

    var imageName: String {
        switch self {
        case .exercise: return "ActivityExercise"
        case .groceries: return "ActivityGroceries"
        case .cleaning: return "ActivityCleaning"
        case .work: return "ActivityWork"
        case .walk: return "ActivityWalk"
        case .shows: return "ActivityShows"
        case .videoGames: return "ActivityVideoGames"
        case .cooking: return "ActivityCooking"
        case .nap: return "ActivityNap"
        case .math: return "ActivityMath"
        case .breadboard: return "ActivityBreadboard"
        case .soldering: return "ActivitySoldering"
        case .reading: return "ActivityReading"
        case .programming: return "ActivityProgramming"
        case .drawing: return "ActivityDrawing"
        case .lego: return "ActivityLego"
        case .music: return "ActivityMusic"
        case .study: return "ActivityStudy"
        case .gamedev: return "ActivityGamedev"
        case .writing: return "ActivityWriting"
        case .modeling3D: return "ActivityModeling3D"
        }
    }
}
