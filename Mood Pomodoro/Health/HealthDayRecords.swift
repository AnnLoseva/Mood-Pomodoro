//
//  HealthDayRecords.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// Cycle and medication read from Apple Health.
///
/// **Local-only, for the same reason `SleepRecord` is** — these are personal
/// health information, and Apple's review guidelines forbid keeping that in
/// iCloud. They live in `LocalHealthStore`, never in
/// `PersistenceController.schema`, and each device reads them from Health
/// itself.
///
/// Both are caches of Health, and both sit *beside* what the user records
/// herself rather than replacing it: `CycleEntry` and `SupportEntry` stay
/// exactly as they were, still sync, and still win wherever she marked a day
/// in the app. Health only fills in the days she didn't.

/// How heavy the bleeding was, as Health records it. The raw values are
/// stable across the `HKCategoryValueMenstrualFlow` → `HKCategoryValueVaginalBleeding`
/// rename, so they are mapped by number and this enum needs no availability
/// gate of its own.
enum MenstrualFlow: Int, Codable, Sendable, CaseIterable, Identifiable {
    case unspecified = 1
    case light = 2
    case medium = 3
    case heavy = 4
    /// "None" is a real answer in Health — a day explicitly marked as having
    /// no bleeding. It is not the same as a day with no record at all.
    case none = 5

    var id: Int { rawValue }

    /// Whether this counts as a day of menstruation.
    var isBleeding: Bool { self != .none }

    var label: String {
        switch self {
        case .unspecified: return L("Без уточнения", "Unspecified")
        case .light: return L("Слабые", "Light")
        case .medium: return L("Умеренные", "Medium")
        case .heavy: return L("Обильные", "Heavy")
        case .none: return L("Нет", "None")
        }
    }
}

/// One day of cycle information from Health.
@Model
final class HealthCycleDay {
    var id: UUID = UUID()
    /// Normalized to `startOfDay` — a cycle mark is a day, not a moment.
    var day: Date = Date.now
    var flowRaw: Int = MenstrualFlow.unspecified.rawValue
    /// Health's own `HKMetadataKeyMenstrualCycleStart`, which is a required
    /// metadata key on these samples. This is what makes counting a cycle
    /// day possible without the app guessing where a cycle began.
    var isCycleStart: Bool = false
    var sourceName: String?
    var importedAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(day: Date, flow: MenstrualFlow, isCycleStart: Bool, sourceName: String?, calendar: Calendar = .current) {
        self.id = UUID()
        self.day = calendar.startOfDay(for: day)
        self.flowRaw = flow.rawValue
        self.isCycleStart = isCycleStart
        self.sourceName = sourceName
        self.importedAt = .now
        self.updatedAt = .now
    }

    var flow: MenstrualFlow {
        get { MenstrualFlow(rawValue: flowRaw) ?? .unspecified }
        set { flowRaw = newValue.rawValue }
    }
}

/// One day's medication logging from Health.
///
/// Health records a *dose event* per scheduled dose, so a day can hold
/// several. This collapses them into one day's answer with the counts kept,
/// using the same three-way vocabulary the app already speaks
/// (`SupportStatus`): taken, not taken, or nothing said.
@Model
final class HealthMedicationDay {
    var id: UUID = UUID()
    var day: Date = Date.now
    var takenCount: Int = 0
    var skippedCount: Int = 0
    var sourceName: String?
    var importedAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(day: Date, takenCount: Int, skippedCount: Int, sourceName: String?, calendar: Calendar = .current) {
        self.id = UUID()
        self.day = calendar.startOfDay(for: day)
        self.takenCount = takenCount
        self.skippedCount = skippedCount
        self.sourceName = sourceName
        self.importedAt = .now
        self.updatedAt = .now
    }

    /// The day's answer in the app's own vocabulary.
    ///
    /// Mixed dose results remain partial, with counts retained in details.
    /// Untouched reminders are not evidence of skipped medication.
    var status: SupportStatus? {
        if takenCount > 0 && skippedCount > 0 { return .partial }
        if takenCount > 0 { return .taken }
        if skippedCount > 0 { return .notTaken }
        return nil
    }

    /// "2 приёма · 1 пропуск", when there was more than one dose that day.
    var detail: String? {
        guard takenCount + skippedCount > 1 else { return nil }
        var parts: [String] = []
        if takenCount > 0 {
            parts.append(countLabel(takenCount, ru: ("приём", "приёма", "приёмов"), en: ("dose", "doses")))
        }
        if skippedCount > 0 {
            parts.append(countLabel(skippedCount, ru: ("пропуск", "пропуска", "пропусков"), en: ("skipped", "skipped")))
        }
        return parts.joined(separator: " · ")
    }
}

/// A cycle mark, whatever recorded it.
///
/// The app's own `CycleEntry` and Health's `HealthCycleDay` describe the
/// same thing in two vocabularies, and cycle day has to be counted across
/// both. This is the shape the counting works on, so neither source has to
/// know about the other.
struct CycleMark: Hashable, Sendable {
    /// Already a calendar day, not a moment — both sources normalize on the
    /// way in (`CycleEntry.date` at init, `HealthCycleDay.day` at import),
    /// each with its own calendar. Re-normalizing here with `.current` would
    /// shift a day that was recorded under a different time zone, so this
    /// deliberately stores what it is given.
    let day: Date
    let kind: CycleEventKind
    let source: SleepSource
}

extension CycleEntry {
    var mark: CycleMark { CycleMark(day: date, kind: kind, source: .manual) }
}

extension HealthCycleDay {
    /// Health's cycle-start metadata maps onto the app's "начало
    /// менструации"; every other bleeding day is a `periodDay`. A day
    /// explicitly marked as *no* bleeding is not a period day and produces
    /// no mark at all.
    var mark: CycleMark? {
        guard flow.isBleeding else { return nil }
        return CycleMark(day: day, kind: isCycleStart ? .periodStart : .periodDay, source: .healthKit)
    }
}
