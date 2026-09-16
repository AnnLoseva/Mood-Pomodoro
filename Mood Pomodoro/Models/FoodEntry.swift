//
//  FoodEntry.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// How the user files a meal for her own observations. These are her three
/// drawers, not a verdict on her: nothing in the app praises "полезная",
/// scolds "вредная", scores a day, counts a calorie or suggests eating
/// differently. The words are labels on records — the same way "Пуэр" is a
/// label on a drink — and every screen that shows them states counts only.
enum FoodCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case healthy
    case regular
    case treat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthy: return L("Полезная", "Wholesome")
        case .regular: return L("Обычная", "Regular")
        case .treat: return L("Вредная", "Junk / treat")
        }
    }

    var imageName: String {
        switch self {
        case .healthy: return "FoodHealthy"
        case .regular: return "FoodRegular"
        case .treat: return "FoodTreat"
        }
    }

    /// For the places an illustration can't go: the export, a one-line
    /// summary, a marker chip.
    var emoji: String {
        switch self {
        case .healthy: return "🥗"
        case .regular: return "🍲"
        case .treat: return "🍫"
        }
    }

    /// Which follow-up questions this category asks. The two branches never
    /// overlap — see `FoodEntry.apply`.
    var usesMealDetails: Bool { self != .treat }
}

/// How much of a meal it was. Asked for `healthy` and `regular` only.
enum MealDensity: String, Codable, Sendable, CaseIterable, Identifiable {
    case light
    case filling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return L("Легко", "Light")
        case .filling: return L("Плотно", "Filling")
        }
    }

    var emoji: String {
        switch self {
        case .light: return "🍃"
        case .filling: return "🥘"
        }
    }
}

/// Whether it was enjoyed. Asked for `healthy` and `regular` only.
enum TasteRating: String, Codable, Sendable, CaseIterable, Identifiable {
    case tasty
    case notGreat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tasty: return L("Вкусно", "Tasty")
        case .notGreat: return L("Не очень", "Not great")
        }
    }

    var emoji: String {
        switch self {
        case .tasty: return "😋"
        case .notGreat: return "😐"
        }
    }
}

/// Which way a treat went. Asked for `treat` only.
enum TreatType: String, Codable, Sendable, CaseIterable, Identifiable {
    case sweet
    case salty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sweet: return L("Сладкое", "Sweet")
        case .salty: return L("Солёное", "Salty")
        }
    }

    var emoji: String {
        switch self {
        case .sweet: return "🍬"
        case .salty: return "🥨"
        }
    }
}

/// How much of it. Asked for `treat` only. "Слишком много" is the user's own
/// word for her own record — the app never repeats it back as a judgement.
enum TreatAmount: String, Codable, Sendable, CaseIterable, Identifiable {
    case little
    case normal
    case tooMuch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .little: return L("Чуть-чуть", "A little")
        case .normal: return L("Нормально", "A normal amount")
        case .tooMuch: return L("Слишком много", "Too much")
        }
    }
}

/// How full she was *after* eating — the other end of `HungerLevel`, which
/// only ever describes the state before. Optional on every food entry: it
/// exists so "съела мало и осталась голодной" and "съела и наелась" can be
/// told apart later, never as a question she has to answer to save a meal.
enum Fullness: String, ScaleStep {
    case overfull
    case full
    case satisfied
    case stillABitHungry
    case stillHungry

    var id: String { rawValue }

    static var orderedCases: [Fullness] { [.overfull, .full, .satisfied, .stillABitHungry, .stillHungry] }

    var scale: Double {
        switch self {
        case .overfull: return 5
        case .full: return 4
        case .satisfied: return 3
        case .stillABitHungry: return 2
        case .stillHungry: return 1
        }
    }

    var label: String {
        switch self {
        case .overfull: return L("Переела", "Overfull")
        case .full: return L("Очень сыта", "Very full")
        case .satisfied: return L("Наелась", "Satisfied")
        case .stillABitHungry: return L("Ещё немного голодна", "Still a bit hungry")
        case .stillHungry: return L("Всё ещё голодна", "Still hungry")
        }
    }

    var emoji: String {
        switch self {
        case .overfull: return "🥴"
        case .full: return "😌"
        case .satisfied: return "🙂"
        case .stillABitHungry: return "😕"
        case .stillHungry: return "🥺"
        }
    }
}

/// One thing eaten, at the moment it was eaten.
///
/// Two shapes live in one model, because one meal is one row in the day
/// whichever drawer it went in. `category` decides which half is filled:
/// `healthy`/`regular` carry `mealDensity` + `taste`, `treat` carries
/// `treatType` + `treatAmount`, and the other half is always nil. Nothing
/// writes a contradictory pair — every write goes through `apply(...)`,
/// which clears the branch that doesn't apply.
///
/// Same date discipline as every other diary record: `eventDate` is when
/// the food happened, `createdAt` when the line was typed. "В 23:00
/// вспомнила, что в 16:30 ела пасту" is an `eventDate` of 16:30.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var eventDate: Date = Date.now
    var categoryRaw: String = FoodCategory.regular.rawValue

    // Filled for .healthy / .regular
    var mealDensityRaw: String?
    var tasteRaw: String?

    // Filled for .treat
    var treatTypeRaw: String?
    var treatAmountRaw: String?

    /// How full she felt afterwards, if she said. Never inferred from
    /// density — "плотно" is how much food there was, not how it landed.
    var fullnessRaw: String?

    /// "Паста с грибами", "Шоколад". Optional and always optional.
    var desc: String?
    var note: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        eventDate: Date,
        category: FoodCategory,
        mealDensity: MealDensity? = nil,
        taste: TasteRating? = nil,
        treatType: TreatType? = nil,
        treatAmount: TreatAmount? = nil,
        fullness: Fullness? = nil,
        desc: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.eventDate = eventDate
        self.categoryRaw = category.rawValue
        self.fullnessRaw = fullness?.rawValue
        self.desc = desc
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
        apply(
            category: category,
            mealDensity: mealDensity,
            taste: taste,
            treatType: treatType,
            treatAmount: treatAmount
        )
    }

    /// The one place the branch rule is enforced: whatever the caller hands
    /// over, only the fields belonging to `category` survive. A meal edited
    /// from "Обычная · Плотно · Вкусно" into "Вредная · Сладкое" must not
    /// keep its old density hanging off the record.
    func apply(
        category: FoodCategory,
        mealDensity: MealDensity?,
        taste: TasteRating?,
        treatType: TreatType?,
        treatAmount: TreatAmount?
    ) {
        self.categoryRaw = category.rawValue
        if category.usesMealDetails {
            self.mealDensityRaw = mealDensity?.rawValue
            self.tasteRaw = taste?.rawValue
            self.treatTypeRaw = nil
            self.treatAmountRaw = nil
        } else {
            self.mealDensityRaw = nil
            self.tasteRaw = nil
            self.treatTypeRaw = treatType?.rawValue
            self.treatAmountRaw = treatAmount?.rawValue
        }
    }

    var category: FoodCategory {
        get { FoodCategory(rawValue: categoryRaw) ?? .regular }
        set {
            apply(
                category: newValue,
                mealDensity: mealDensity,
                taste: taste,
                treatType: treatType,
                treatAmount: treatAmount
            )
        }
    }

    /// Readers return nil whenever the field doesn't belong to the current
    /// category, so even a row an older build or a half-finished sync left
    /// inconsistent reads as the shape its category promises.
    var mealDensity: MealDensity? {
        guard category.usesMealDetails else { return nil }
        return mealDensityRaw.flatMap(MealDensity.init(rawValue:))
    }

    var taste: TasteRating? {
        guard category.usesMealDetails else { return nil }
        return tasteRaw.flatMap(TasteRating.init(rawValue:))
    }

    var treatType: TreatType? {
        guard !category.usesMealDetails else { return nil }
        return treatTypeRaw.flatMap(TreatType.init(rawValue:))
    }

    var treatAmount: TreatAmount? {
        guard !category.usesMealDetails else { return nil }
        return treatAmountRaw.flatMap(TreatAmount.init(rawValue:))
    }

    var fullness: Fullness? {
        get { fullnessRaw.flatMap(Fullness.init(rawValue:)) }
        set { fullnessRaw = newValue?.rawValue }
    }

    /// "Полезная · Плотно · Вкусно" — only the parts that were answered.
    var detailLine: String {
        var parts = [category.label]
        if let mealDensity { parts.append(mealDensity.label) }
        if let taste { parts.append(taste.label) }
        if let treatType { parts.append(treatType.label) }
        if let treatAmount { parts.append(treatAmount.label) }
        return parts.joined(separator: " · ")
    }
}
