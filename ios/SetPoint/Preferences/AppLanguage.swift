import SwiftUI

/// In-app language. English and Hebrew — the two catalogs we ship.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case he

    var id: String { rawValue }

    static let storageKey = "com.setpoint.app.language"

    /// Hebrew if the phone is Hebrew; English otherwise. Replaces a leftover
    /// "system" value from an earlier build.
    static var localeDefault: AppLanguage {
        Locale.current.language.languageCode?.identifier == "he" ? .he : .en
    }

    var title: String {
        switch self {
        case .en: return "אנגלית"
        case .he: return "עברית"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// Gregorian calendar whose weekday names follow this language (Sunday-first in Hebrew).
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        if self == .he { calendar.firstWeekday = 1 }
        return calendar
    }

    /// The compiled `he.lproj` / `en.lproj`. `String(localized:locale:)` alone
    /// still reads the phone language; this bundle is what the settings control picks.
    var stringsBundle: Bundle {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    /// What the settings control last wrote. `String(localized:)` ignores the
    /// SwiftUI locale environment — use `L10n` so copy follows this, not the phone.
    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? localeDefault
    }
}

/// Looks up a catalog string in the in-app language.
func L10n(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AppLanguage.current.stringsBundle, locale: AppLanguage.current.locale)
}

/// Looks up a catalog key held in a `String` (food names, On/Off, unit codes).
func L10nKey(_ key: String) -> String {
    String(localized: String.LocalizationValue(stringLiteral: key), bundle: AppLanguage.current.stringsBundle, locale: AppLanguage.current.locale)
}

/// Pins locale and reading direction to the chosen language.
struct AppLanguageReader: ViewModifier {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.localeDefault

    func body(content: Content) -> some View {
        content.environment(\.locale, language.locale)
    }
}