//
//  FactorCategory.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// A user-facing "condition" category — what was going on around the user
/// (music, drink, sleep, place, …). Data-driven on purpose: nothing in the
/// UI hardcodes a category or its options, so adding/renaming/disabling one
/// is a data change, not a code change (the groundwork for a future editor
/// screen, even though that editor doesn't exist yet).
@Model
final class FactorCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    /// Illustrated icon asset name, when this category has custom art
    /// (falls back to the `icon` emoji when nil — e.g. for categories the
    /// user adds later, which won't have matching artwork).
    var iconImageName: String?
    var isEnabled: Bool
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \FactorOption.category)
    var options: [FactorOption] = []

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        iconImageName: String? = nil,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.iconImageName = iconImageName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    var enabledOptions: [FactorOption] {
        options.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// One selectable value within a `FactorCategory` (e.g. "Lo-fi" under "Музыка").
@Model
final class FactorOption {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    /// Illustrated icon specific to this option (e.g. the drinks each have
    /// their own artwork rather than sharing the category's). Falls back to
    /// the category's icon, then its emoji, when nil.
    var iconImageName: String?
    var isEnabled: Bool
    var sortOrder: Int
    var category: FactorCategory?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        iconImageName: String? = nil,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.iconImageName = iconImageName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }
}

/// An immutable, denormalized copy of "what condition was active" — stamped
/// onto a `CheckIn` at the moment it's created and never touched again.
/// Snapshotting (rather than a live relationship lookup) is what guarantees
/// old check-ins keep showing the condition that was actually true then,
/// even after the user renames/disables a category or option, or changes
/// the condition later in the same session.
struct ConditionSnapshotEntry: Codable, Hashable, Identifiable {
    var categoryID: UUID
    var categoryName: String
    var categoryIcon: String
    var categoryIconImageName: String?
    var optionID: UUID
    var optionName: String
    var optionIconImageName: String?

    var id: UUID { categoryID }

    /// The most specific icon available: the option's own art, else the
    /// category's, else nil (render the emoji instead).
    var resolvedIconImageName: String? { optionIconImageName ?? categoryIconImageName }
}
