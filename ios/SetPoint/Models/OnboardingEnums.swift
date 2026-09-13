import Foundation

enum Goal: String, CaseIterable, Identifiable {
    case bulk = "BULK"
    case diet = "DIET"
    case maintain = "MAINTAIN"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bulk: return "Gain"
        case .diet: return "Cut"
        case .maintain: return "Maintain"
        }
    }
    var blurb: String {
        switch self {
        case .bulk: return "Gain size consistently."
        case .diet: return "Lose fat safely."
        case .maintain: return "Keep weight steady."
        }
    }

    /// Whether this goal needs a target weight + pace.
    var hasWeightTarget: Bool { self != .maintain }

    var directionVerb: String {
        switch self {
        case .bulk: return "Gain to"
        case .diet: return "Cut to"
        case .maintain: return "Hold at"
        }
    }
}

/// How fast a weight goal should move (M16). The kg/week value is goal-aware —
/// gaining muscle sustainably is slower than losing fat.
enum GoalPace: String, CaseIterable, Identifiable {
    case gentle = "GENTLE"
    case steady = "STEADY"

    var id: String { rawValue }
    var title: String { self == .gentle ? "Gentle" : "Steady" }

    func kgPerWeek(for goal: Goal) -> Double {
        switch (goal, self) {
        case (.bulk, .gentle): return 0.12
        case (.bulk, .steady): return 0.25
        case (.diet, .gentle): return 0.35
        case (.diet, .steady): return 0.6
        default: return 0
        }
    }

    func blurb(for goal: Goal) -> String {
        let kg = kgPerWeek(for: goal)
        return String(format: "%.2f kg/wk", kg)
    }

    /// The pace whose rate is nearest a stored kg/week value.
    static func closest(toKgPerWeek kg: Double, for goal: Goal) -> GoalPace {
        allCases.min { abs($0.kgPerWeek(for: goal) - kg) < abs($1.kgPerWeek(for: goal) - kg) } ?? .gentle
    }
}

enum Sex: String, CaseIterable, Identifiable {
    case male = "MALE"
    case female = "FEMALE"
    case unspecified = "UNSPECIFIED"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .unspecified: return "Prefer not to say"
        }
    }
}

/// A whole-rhythm preset for the onboarding Rhythm step — picking one sets all
/// three meal anchors (and, derived from them, quiet hours) in a single tap,
/// instead of five separate time pickers.
enum MealRhythmPreset: String, CaseIterable, Identifiable {
    case standard, early, night, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .early: return "Early bird"
        case .night: return "Night owl"
        case .custom: return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "8:00 · 13:00 · 19:00"
        case .early: return "6:00 · 11:00 · 17:00"
        case .night: return "10:00 · 15:00 · 21:00"
        case .custom: return "Set your own times"
        }
    }

    /// Breakfast / lunch / dinner, minutes from local midnight. Nil for `.custom`.
    var times: (breakfast: Int, lunch: Int, dinner: Int)? {
        switch self {
        case .standard: return (480, 780, 1140)
        case .early: return (360, 660, 1020)
        case .night: return (600, 900, 1260)
        case .custom: return nil
        }
    }

    /// The preset closest to a stored set of meal anchors — used when editing
    /// an existing draft so the right card shows selected.
    static func closest(breakfast: Int, lunch: Int, dinner: Int) -> MealRhythmPreset {
        for preset in [standard, early, night] {
            if preset.times.map({ $0 == (breakfast, lunch, dinner) }) == true { return preset }
        }
        return .custom
    }
}

/// Quiet hours implied by a meal rhythm — check-ins never fire from soon after
/// dinner until shortly before breakfast. Derived, not asked, so onboarding
/// doesn't need two more time pickers; still editable later in Settings.
func derivedQuietHours(breakfastMin: Int, dinnerMin: Int) -> (start: Int, end: Int) {
    let start = (dinnerMin + 240) % 1440
    let end = max(0, breakfastMin - 60)
    return (start, end)
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary = "SEDENTARY"
    case light = "LIGHT"
    case moderate = "MODERATE"
    case active = "ACTIVE"
    case veryActive = "VERY_ACTIVE"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sedentary: return "Sitting"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }

    var blurb: String {
        switch self {
        case .sedentary: return "Mostly sitting, little exercise."
        case .light: return "Light exercise 1–3 days a week."
        case .moderate: return "Moderate exercise 3–5 days a week."
        case .active: return "Hard exercise 6–7 days a week."
        case .veryActive: return "Very hard exercise, or a physical job."
        }
    }
}
