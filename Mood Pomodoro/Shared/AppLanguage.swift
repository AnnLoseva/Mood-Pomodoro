//
//  AppLanguage.swift
//  Mood Pomodoro
//
//  The app's own language switch (Русский / English), independent of the
//  device language — so the diary can be shown to someone who doesn't read
//  Russian without changing the whole phone. Compiled into the app and the
//  Live Activity widget.
//
//  Strings are written in place as `L("русский", "English")` rather than
//  kept in a String Catalog: most of the UI passes plain `String`s through
//  shared components, and model-level text (moods, statuses, notification
//  actions) has to switch too — a catalog keyed off `\.locale` would only
//  cover the literal `Text("…")` half of that.
//

import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case ru
    case en

    static let storageKey = "app.language"

    var id: String { rawValue }

    /// Set while building something in a language other than the UI's —
    /// e.g. an English export from a Russian-language app.
    @TaskLocal static var override: AppLanguage?

    static var current: AppLanguage {
        if let override { return override }
        return UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .ru
    }

    var locale: Locale { Locale(identifier: self == .ru ? "ru_RU" : "en_US") }

    /// Each language named in itself, so the switch is readable either way.
    var nativeName: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

/// The string for the current language.
nonisolated func L(_ ru: String, _ en: String) -> String {
    L(ru, en, in: .current)
}

nonisolated func L(_ ru: String, _ en: String, in language: AppLanguage) -> String {
    language == .en ? en : ru
}

/// "1 сессия / 3 сессии / 5 сессий" · "1 session / 3 sessions".
nonisolated func countLabel(
    _ count: Int,
    ru: (one: String, few: String, many: String),
    en: (one: String, other: String)
) -> String {
    switch AppLanguage.current {
    case .en:
        return "\(count) \(count == 1 ? en.one : en.other)"
    case .ru:
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = ru.one
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = ru.few
        } else {
            word = ru.many
        }
        return "\(count) \(word)"
    }
}

/// "3 check-in" — the app uses the English word in both languages.
nonisolated func checkInCount(_ count: Int) -> String {
    AppLanguage.current == .en ? "\(count) check-in\(count == 1 ? "" : "s")" : "\(count) check-in"
}
