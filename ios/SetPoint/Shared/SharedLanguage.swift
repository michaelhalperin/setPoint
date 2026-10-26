import SwiftUI

/// The in-app language, shared with the widgets and Live Activity through the
/// app group — they can't read the app's own defaults. The app writes it
/// whenever the Language setting changes; until then they follow the phone.
enum SharedLanguage {
    static let key = "language"

    static var code: String {
        if let stored = AppGroup.defaults.string(forKey: key), stored == "he" || stored == "en" { return stored }
        return Locale.current.language.languageCode?.identifier == "he" ? "he" : "en"
    }

    static var locale: Locale { Locale(identifier: code) }

    static var layoutDirection: LayoutDirection { code == "he" ? .rightToLeft : .leftToRight }

    /// The app calls this when the language (or whether the picker is on) changes.
    static func publish(_ code: String) {
        AppGroup.defaults.set(code, forKey: key)
    }

    private static var bundle: Bundle {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    /// A catalog string in the shared language, for copy built in code.
    static func tr(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }
}

extension View {
    /// Widgets and Live Activities read their language and direction from here.
    func sharedLanguage() -> some View {
        environment(\.locale, SharedLanguage.locale)
            .environment(\.layoutDirection, SharedLanguage.layoutDirection)
    }
}
