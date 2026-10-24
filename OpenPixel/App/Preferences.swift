import SwiftUI

/// UI language. English is the default; it doesn't follow the device language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    /// Each language names itself, so it can be found whatever the current language is.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        }
    }

    static let storageKey = "language"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .english
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    static let storageKey = "appearance"

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app's accent color: selected tools, buttons, toggles and highlights.
enum AccentChoice: String, CaseIterable, Identifiable {
    case ember, blue, green, purple, pink

    var id: String { rawValue }
    static let storageKey = "accentColor"

    static var current: AccentChoice {
        AccentChoice(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .ember
    }

    var title: LocalizedStringKey {
        switch self {
        case .ember: "Ember"
        case .blue: "Blue"
        case .green: "Green"
        case .purple: "Purple"
        case .pink: "Pink"
        }
    }

    struct Shades {
        let accent: (light: UInt32, dark: UInt32)
        /// Background of selected chips.
        let soft: (light: UInt32, dark: UInt32)
        /// Text on `soft`.
        let text: (light: UInt32, dark: UInt32)
    }

    var shades: Shades {
        switch self {
        case .ember: Shades(accent: (0xC9461F, 0xFF7A59), soft: (0xFBE6DF, 0x2A211E), text: (0xB23C18, 0xFFB29E))
        case .blue: Shades(accent: (0x2563EB, 0x6AA2FF), soft: (0xE1EBFD, 0x1C2333), text: (0x1D4FC4, 0xA9C6FF))
        case .green: Shades(accent: (0x1F8A4C, 0x4CD08A), soft: (0xDDF3E6, 0x1A2A21), text: (0x17703D, 0x9BE7BE))
        case .purple: Shades(accent: (0x7C3AED, 0xA78BFA), soft: (0xEDE5FD, 0x241E33), text: (0x6528D0, 0xCDBDFD))
        case .pink: Shades(accent: (0xD6336C, 0xFF7AA8), soft: (0xFBE3EC, 0x2E1D24), text: (0xB8255A, 0xFFB3CE))
        }
    }

    /// A swatch for the picker, in the current appearance.
    var swatch: Color { Theme.adaptive(light: shades.accent.light, dark: shades.accent.dark) }
}

/// Localized strings built outside SwiftUI views (notices, default names),
/// in the language chosen in Preferences rather than the device language.
enum L10n {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let language = AppLanguage.current.rawValue
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: AppLanguage.current.locale, arguments: arguments)
    }
}
