//
//  LanguageMenu.swift
//  Mood Pomodoro
//

import SwiftUI

/// The globe button that switches the app between Русский and English.
/// Writing the choice to `@AppStorage` is all it does — the app root
/// observes the same key and rebuilds every screen in the new language.
struct LanguageMenu: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.ru.rawValue

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageRaw = language.rawValue
                } label: {
                    if language.rawValue == languageRaw {
                        Label(language.nativeName, systemImage: "checkmark")
                    } else {
                        Text(language.nativeName)
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.forest)
        }
        .accessibilityLabel(L("Язык", "Language"))
    }
}
