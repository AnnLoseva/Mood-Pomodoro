//
//  ActivityCategory.swift
//  Mood Pomodoro
//

import Foundation

/// Optional quick-pick activity categories shown on the New Session screen.
/// Purely a UI convenience — picking one just fills in the free-text
/// activity field, it isn't stored as its own attribute on `FocusSession`.
enum ActivityCategory: String, CaseIterable, Identifiable {
    case math
    case electronics
    case reading
    case notes
    case code
    case plans
    case creativity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .math: return "Математика"
        case .electronics: return "Электроника"
        case .reading: return "Чтение"
        case .notes: return "Заметки"
        case .code: return "Код"
        case .plans: return "Планы"
        case .creativity: return "Творчество"
        }
    }

    /// `label` is what gets stored on a session (it stays Russian so history
    /// doesn't fork by language); this is what's shown.
    var displayLabel: String { Ldata(label) }

    var imageName: String {
        switch self {
        case .math: return "ActivityMath"
        case .electronics: return "ActivityElectronics"
        case .reading: return "ActivityReading"
        case .notes: return "ActivityNotes"
        case .code: return "ActivityCode"
        case .plans: return "ActivityPlans"
        case .creativity: return "ActivityCreativity"
        }
    }
}
