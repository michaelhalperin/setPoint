import Foundation

/// Food names and serving descriptions come from the server in English (the
/// staple-food list). In Hebrew they're translated here: names through the
/// string catalog, serving descriptions word by word.
enum FoodText {
    /// "Rotisserie chicken" → "עוף צלוי". Combined names ("A + B", "A, B") are
    /// translated piece by piece; anything not in the catalog stays as it is.
    static func name(_ text: String) -> String {
        guard AppLanguage.current == .he else { return text }
        let whole = L10nKey(text)
        if whole != text { return whole }
        for separator in [" + ", " · ", ", "] where text.contains(separator) {
            return text.components(separatedBy: separator).map { name($0) }.joined(separator: separator)
        }
        return text
    }

    /// "1 cup (240 ml)" → "1 כוס (240 מ״ל)".
    static func serving(_ text: String) -> String {
        guard AppLanguage.current == .he else { return text }
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
        guard AppLanguage.current == .he else { return text }
        let whole = L10nKey(text)
        if whole != text { return whole }
        if let match = text.firstMatch(of: /^(\d+) kcal under target\.$/), let kcal = Int(match.1) {
            return L10n("\(kcal) kcal under target.")
        }
        return text
    }
}
