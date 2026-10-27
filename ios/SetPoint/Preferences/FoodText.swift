import Foundation

/// Food names and serving descriptions come from the server in English (the
/// staple-food list). In Hebrew they're translated here: names through the
/// string catalog, serving descriptions word by word.
enum FoodText {
    /// Text the app stored in one language (a meal summary, a snack suggestion,
    /// "Top-up: …") shown in the language that's on now. Known food names and
    /// phrases flip both ways; anything else — what someone typed — is left alone.
    static func name(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let whole = translated(trimmed) { return whole }
        // "2 × חלב מלא + שקדים": the quantity, then each piece on its own.
        for (prefixes, replacement) in affixes {
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                return replacement + name(String(trimmed.dropFirst(prefix.count)))
            }
        }
        for suffix in roughEstimate where trimmed.hasSuffix(suffix.0) {
            return name(String(trimmed.dropLast(suffix.0.count))) + suffix.1
        }
        for separator in [" + ", " · ", ", "] where trimmed.contains(separator) {
            return trimmed.components(separatedBy: separator).map { name($0) }.joined(separator: separator)
        }
        if let match = trimmed.firstMatch(of: /^(\d+(?:\.\d+)?) × (.+)$/) {
            return "\(match.1) × \(name(String(match.2)))"
        }
        return text
    }

    private static let affixes: [([String], String)] = [
        (["Top-up: ", "תוספת: "], L10n("Top-up: ")),
    ]

    private static let roughEstimate: [(String, String)] = [
        (" (rough estimate)", " (" + L10n("rough estimate") + ")"),
        (" (הערכה גסה)", " (" + L10n("rough estimate") + ")"),
    ]

    static func exact(_ text: String) -> String? { translated(text) }

    /// The catalog entry for this text in the current language, if it has one.
    private static func translated(_ text: String) -> String? {
        if AppLanguage.current == .he {
            let hebrew = L10nKey(text)
            return hebrew == text ? nil : hebrew
        }
        return englishForHebrew[text]
    }

    /// Hebrew catalog values back to their English keys, for text stored while the app was in Hebrew.
    private static let englishForHebrew: [String: String] = {
        guard let path = Bundle.main.path(forResource: "he", ofType: "lproj"),
              let table = NSDictionary(contentsOfFile: path + "/Localizable.strings") as? [String: String]
        else { return [:] }
        var reverse: [String: String] = [:]
        for (key, value) in table where !key.contains("%") && !value.contains("%") {
            let clean = value.replacingOccurrences(of: "\u{200F}", with: "")
            if reverse[clean] == nil || key.count < (reverse[clean] ?? "").count { reverse[clean] = key }
        }
        return reverse
    }()

    /// "1 cup (240 ml)" → "1 כוס (240 מ״ל)".
    static func serving(_ text: String) -> String {
        if AppLanguage.current != .he { return translated(text) ?? text }
        var result = text
        for (english, hebrew) in servingWords {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: english) + "(?![A-Za-z])"
            result = result.replacingOccurrences(of: pattern, with: hebrew, options: .regularExpression)
        }
        return result
    }

    /// Longest phrases first so "cream cheese" wins over "cheese".
    private static let servingWords: [(String, String)] = [
        ("cottage cheese", "קוטג׳"), ("cream cheese", "גבינת שמנת"), ("egg salad", "סלט ביצים"),
        ("with a pat of butter", "עם קצת חמאה"), ("small box", "קופסה קטנה"), ("in water", "במים"),
        ("slices", "פרוסות"), ("slice", "פרוסה"), ("cups", "כוסות"), ("cup", "כוס"),
        ("tbsp", "כפות"), ("tsp", "כפיות"), ("oz", "אונקיות"), ("ml", "מ״ל"), ("g", "גר׳"),
        ("large eggs", "ביצים גדולות"), ("eggs", "ביצים"), ("large", "גדול"), ("medium", "בינוני"),
        ("bottle", "בקבוק"), ("bar", "חטיף"), ("can", "קופסה"), ("burrito", "בוריטו"),
        ("bagel", "בייגל"), ("muffin", "מאפין"), ("packet", "שקית"), ("patties", "קציצות"),
        ("patty", "קציצה"), ("link", "נקניקייה"), ("scoop", "מידה"), ("sticks", "מקלות"),
        ("cakes", "פריכיות"), ("pancakes", "פנקייקים"), ("rolls", "לחמניות"),
        ("tortillas", "טורטיות"), ("waffles", "וופלים"), ("crackers", "קרקרים"), ("dates", "תמרים"),
        ("cooked", "מבושל"), ("baked", "אפוי"), ("drained", "מסונן"), ("unsweetened", "לא ממותק"),
        ("prepared", "מוכן"), ("kernels", "גרעינים"), ("dry", "יבש"), ("mixed", "מעורב"),
        ("bread", "לחם"), ("toast", "טוסט"), ("banana", "בננה"), ("cheese", "גבינה"),
        ("tuna", "טונה"), ("turkey", "הודו"), ("jam", "ריבה"), ("PB", "חמאת בוטנים"),
        ("apple", "תפוח"), ("cereal", "דגני בוקר"), ("milk", "חלב"), ("fruit", "פירות"),
        ("yogurt", "יוגורט"), ("granola", "גרנולה"), ("oats", "שיבולת שועל"), ("chia", "צ׳יה"),
        ("berries", "פירות יער"), ("romaine", "חסה"), ("chicken", "עוף"), ("rice", "אורז"),
        ("beans", "שעועית"), ("veg", "ירקות"), ("dressing", "רוטב"), ("protein", "חלבון"),
    ]
}

/// The few fixed sentences the server writes (day summaries, "dish ideas").
/// Newer ones already arrive in the person's language; this covers the rest.
enum ServerCopy {
    /// "412 kcal under target." and the other day-summary lines.
    static func line(_ text: String) -> String {
        if let whole = FoodText.exact(text) { return whole }
        if let match = text.firstMatch(of: /^(\d+) (?:kcal under target\.|קלוריות מתחת ליעד\.)$/), let kcal = Int(match.1) {
            return L10n("\(kcal) kcal under target.")
        }
        return text
    }
}
