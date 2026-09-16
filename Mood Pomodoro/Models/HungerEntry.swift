//
//  HungerEntry.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// How much the *body* is asking for food. Physical only — whether anything
/// sounds appealing is `AppetiteLevel`, a separate answer to a separate
/// question. The two are never derived from each other: "физически голодна,
/// но есть не хочется" (hunger 4, appetite 1) and "сыта, но тянет поесть"
/// (hunger 1, appetite 5) are both perfectly valid records.
enum HungerLevel: String, LevelScale {
    case veryHungry
    case hungry
    case wantingToEat
    case slightlyHungry
    case notHungry

    var id: String { rawValue }

    /// Ordered the way every other picker in the app is: the "most" end
    /// first. For hunger that is "очень сильный голод".
    static var orderedCases: [HungerLevel] { [.veryHungry, .hungry, .wantingToEat, .slightlyHungry, .notHungry] }

    var scale: Double {
        switch self {
        case .veryHungry: return 5
        case .hungry: return 4
        case .wantingToEat: return 3
        case .slightlyHungry: return 2
        case .notHungry: return 1
        }
    }

    var label: String {
        switch self {
        case .veryHungry: return L("Очень сильный голод", "Very strong hunger")
        case .hungry: return L("Очень голодна", "Very hungry")
        case .wantingToEat: return L("Уже хочется поесть", "Starting to want food")
        case .slightlyHungry: return L("Немного голодна", "A little hungry")
        case .notHungry: return L("Совсем не голодна", "Not hungry at all")
        }
    }

    var imageName: String {
        switch self {
        case .veryHungry: return "HungerVeryHungry"
        case .hungry: return "HungerHungry"
        case .wantingToEat: return "HungerWanting"
        case .slightlyHungry: return "HungerSlightly"
        case .notHungry: return "HungerNotHungry"
        }
    }

    /// Used where an illustration can't be drawn — a one-line timeline row,
    /// the diary export. How much food the body is asking for, growing from
    /// a leaf to a laid plate. Deliberately not faces: those belong to
    /// appetite, which is a different question, and to mood, which is a
    /// different scale again.
    var emoji: String {
        switch self {
        case .veryHungry: return "🍽"
        case .hungry: return "🥣"
        case .wantingToEat: return "🥄"
        case .slightlyHungry: return "🫐"
        case .notHungry: return "🍃"
        }
    }
}

/// How much she *wants* to eat — the pull toward food, whatever the body is
/// doing. See `HungerLevel` for why this is kept strictly apart.
enum AppetiteLevel: String, LevelScale {
    case veryHigh
    case high
    case normal
    case low
    case noAppetite

    var id: String { rawValue }

    static var orderedCases: [AppetiteLevel] { [.veryHigh, .high, .normal, .low, .noAppetite] }

    var scale: Double {
        switch self {
        case .veryHigh: return 5
        case .high: return 4
        case .normal: return 3
        case .low: return 2
        case .noAppetite: return 1
        }
    }

    var label: String {
        switch self {
        case .veryHigh: return L("Очень хочется что-нибудь съесть", "Really want to eat something")
        case .high: return L("Хочется есть", "Feel like eating")
        case .normal: return L("Нормальный аппетит", "Normal appetite")
        case .low: return L("Скорее не хочется", "Not really in the mood to eat")
        case .noAppetite: return L("Есть вообще не хочется", "No desire to eat at all")
        }
    }

    var imageName: String {
        switch self {
        case .veryHigh: return "AppetiteVeryHigh"
        case .high: return "AppetiteHigh"
        case .normal: return "AppetiteNormal"
        case .low: return "AppetiteLow"
        case .noAppetite: return "AppetiteNone"
        }
    }

    var emoji: String {
        switch self {
        case .veryHigh: return "🤤"
        case .high: return "😋"
        case .normal: return "🙂"
        case .low: return "😐"
        case .noAppetite: return "😶"
        }
    }
}

/// One moment's hunger and appetite, recorded together because they are
/// usually noticed together — but stored as two independent optionals, so
/// answering only one is a complete record and the other stays "не
/// отмечено" rather than being guessed at.
///
/// `eventDate` is the moment this was *about*; `createdAt` is when it was
/// written. Analytics only ever reads `eventDate`, so a 16:20 hunger typed
/// in at 23:00 sits at 16:20 in the day.
@Model
final class HungerEntry {
    var id: UUID = UUID()
    var eventDate: Date = Date.now
    var hungerRaw: String?
    var appetiteRaw: String?
    var note: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        eventDate: Date,
        hunger: HungerLevel? = nil,
        appetite: AppetiteLevel? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.eventDate = eventDate
        self.hungerRaw = hunger?.rawValue
        self.appetiteRaw = appetite?.rawValue
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    var hunger: HungerLevel? {
        get { hungerRaw.flatMap(HungerLevel.init(rawValue:)) }
        set { hungerRaw = newValue?.rawValue }
    }

    var appetite: AppetiteLevel? {
        get { appetiteRaw.flatMap(AppetiteLevel.init(rawValue:)) }
        set { appetiteRaw = newValue?.rawValue }
    }

    /// A record with neither scale answered says nothing; the forms refuse
    /// to save one, and readers skip any that sync leaves behind.
    var isEmpty: Bool { hunger == nil && appetite == nil }

    /// "Голод: 4/5 · Аппетит: 2/5", naming only what was actually answered.
    var summaryLine: String {
        var parts: [String] = []
        if let hunger {
            parts.append(L("Голод: \(Int(hunger.scale))/5", "Hunger: \(Int(hunger.scale))/5"))
        }
        if let appetite {
            parts.append(L("Аппетит: \(Int(appetite.scale))/5", "Appetite: \(Int(appetite.scale))/5"))
        }
        return parts.joined(separator: " · ")
    }
}
