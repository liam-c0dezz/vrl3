//
//  AppLanguage.swift
//  Construction Estimate
//
//  Instant, app-wide English ⇄ Spanish switching.
//
//  English is the source language. Wrap any user-facing English string in
//  `L(...)` and add its Spanish translation to
//  `Resources/Localization/Translations-es.json`:
//
//      Text(L("Continue"))
//      Text(L("%@ items", "\(count)"))
//
//  `L` reads `LanguageStore.shared.current`, which is `@Observable`, so any
//  SwiftUI view that calls it while rendering re-renders automatically when
//  the language changes. Strings missing from the JSON fall back to English.
//

import Foundation
import Observation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .english: "EN"
        case .spanish: "ES"
        }
    }

    /// The language's own name, as a speaker of it would read it.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        }
    }

    var toggled: AppLanguage {
        self == .english ? .spanish : .english
    }

    /// Locale for dates and numbers. Spanish uses `es_US` so prices keep
    /// US-style separators ($1,234.56) while dates and months read in Spanish.
    var formattingLocale: Locale {
        switch self {
        case .english: .autoupdatingCurrent
        case .spanish: Locale(identifier: "es_US")
        }
    }

    /// The language the app runs in for this user: their in-app choice if they
    /// made one (stored as the app's `AppleLanguages` override, which iOS's
    /// per-app language setting also writes), otherwise the device language.
    static var preferred: AppLanguage {
        let code = UserDefaults.standard.stringArray(forKey: appleLanguagesKey)?.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return code.lowercased().hasPrefix("es") ? .spanish : .english
    }

    fileprivate static let appleLanguagesKey = "AppleLanguages"
}

@Observable
nonisolated final class LanguageStore: @unchecked Sendable {
    static let shared = LanguageStore()

    /// Only mutated on the main thread through `setLanguage(_:)`.
    private(set) var current: AppLanguage

    private let spanish: [String: String]

    private init() {
        current = AppLanguage.preferred
        spanish = Self.loadTranslations(named: "Translations-es")
    }

    /// Switches every screen immediately and remembers the choice. The
    /// `AppleLanguages` override also moves system-provided UI (photo picker,
    /// share sheet, keyboard) to the same language from the next launch.
    func setLanguage(_ language: AppLanguage) {
        guard language != current else { return }
        current = language
        UserDefaults.standard.set([language.rawValue], forKey: AppLanguage.appleLanguagesKey)
    }

    func translate(_ english: String) -> String {
        switch current {
        case .english: english
        case .spanish: spanish[english] ?? english
        }
    }

    private static func loadTranslations(named name: String) -> [String: String] {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let table = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            assertionFailure("Missing or invalid \(name).json")
            return [:]
        }
        return table
    }
}

/// Locale for user-visible dates and numbers in the current app language.
nonisolated var appLocale: Locale {
    LanguageStore.shared.current.formattingLocale
}

/// Translates an English UI string into the current app language.
nonisolated func L(_ english: String) -> String {
    LanguageStore.shared.translate(english)
}

/// Translates an English `String(format:)` template, then fills it in.
nonisolated func L(_ englishFormat: String, _ arguments: CVarArg...) -> String {
    let store = LanguageStore.shared
    return String(
        format: store.translate(englishFormat),
        locale: store.current.formattingLocale,
        arguments: arguments
    )
}
