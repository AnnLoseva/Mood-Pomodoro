//
//  ConditionEvent.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// A timestamped "this condition changed" record — the source of truth for
/// what was true at any moment in a session. A session can have several
/// events for the same category (coffee at 10:00, pu-erh at 10:45); the
/// active value for a category at time T is whichever event for that
/// category has the latest timestamp <= T. Denormalizes names/icons for the
/// same reason `ConditionSnapshotEntry` does: history shouldn't shift under
/// the user's feet if they later rename or disable a category/option.
@Model
final class ConditionEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var categoryID: UUID
    var categoryName: String
    var categoryIcon: String
    var categoryIconImageName: String?
    var optionID: UUID
    var optionName: String
    var optionIconImageName: String?
    var session: FocusSession?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: FactorCategory,
        option: FactorOption
    ) {
        self.id = id
        self.timestamp = timestamp
        self.categoryID = category.id
        self.categoryName = category.name
        self.categoryIcon = category.icon
        self.categoryIconImageName = category.iconImageName
        self.optionID = option.id
        self.optionName = option.name
        self.optionIconImageName = option.iconImageName
    }

    var asSnapshotEntry: ConditionSnapshotEntry {
        ConditionSnapshotEntry(
            categoryID: categoryID,
            categoryName: categoryName,
            categoryIcon: categoryIcon,
            categoryIconImageName: categoryIconImageName,
            optionID: optionID,
            optionName: optionName,
            optionIconImageName: optionIconImageName
        )
    }
}
