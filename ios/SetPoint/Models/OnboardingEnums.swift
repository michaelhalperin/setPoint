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

    /// The two-to-four-word line on the onboarding goal tile.
    var tagline: String {
        switch self {
        case .bulk: return "Build size"
        case .diet: return "Lose fat, keep energy"
        case .maintain: return "Hold steady"
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

/// Safety caps and timeframe math, mirrored from the backend's `targets.ts`.
/// Duration is the input; pace is derived then clamped. The honest week count
/// is remaining ÷ clamped pace — a short ask is never stored past the cap.
enum WeightPace {
    static let minKgPerWeek = 0.1
    static let dietMaxFractionPerWeek = 0.0075
    static let bulkMaxKgPerWeek = 0.5
    static let minWeeks = 1
    static let maxWeeks = 104

    static func remainingKg(goal: Goal, currentKg: Double, targetKg: Double) -> Double {
        let delta = goal == .bulk ? targetKg - currentKg : currentKg - targetKg
        return max(0, delta)
    }

    static func clampKgPerWeek(goal: Goal, weightKg: Double?, pace: Double) -> Double {
        if goal == .maintain { return 0 }
        let magnitude = abs(pace) > 0 ? abs(pace) : minKgPerWeek
        let ceiling: Double
        if goal == .diet, let weightKg {
            ceiling = max(minKgPerWeek, weightKg * dietMaxFractionPerWeek)
        } else {
            ceiling = bulkMaxKgPerWeek
        }
        return (min(max(magnitude, minKgPerWeek), ceiling) * 100).rounded() / 100
    }

    static func clampWeeks(_ weeks: Int) -> Int {
        min(maxWeeks, max(minWeeks, weeks))
    }

    static func etaWeeks(remainingKg: Double, paceKgPerWeek: Double) -> Int? {
        guard remainingKg > 0.05, paceKgPerWeek > 0 else { return nil }
        return Int((remainingKg / paceKgPerWeek).rounded(.up))
    }

    /// Matches backend `resolveGoalPace`. Duration wins when both are present.
    static func resolve(
        goal: Goal,
        weightKg: Double?,
        remainingKg: Double?,
        preferredWeeks: Int?,
        paceKgPerWeek: Double
    ) -> (paceKgPerWeek: Double, preferredDurationWeeks: Int?) {
        if goal == .maintain { return (0, nil) }
        let requestedPace: Double
        if let preferredWeeks, preferredWeeks > 0, let remainingKg, remainingKg > 0 {
            requestedPace = remainingKg / Double(preferredWeeks)
        } else {
            requestedPace = paceKgPerWeek
        }
        let pace = clampKgPerWeek(goal: goal, weightKg: weightKg, pace: requestedPace)
        var weeks = remainingKg.flatMap { etaWeeks(remainingKg: $0, paceKgPerWeek: pace) }
        if weeks == nil, let preferredWeeks, preferredWeeks > 0 {
            weeks = preferredWeeks
        }
        return (pace, weeks.map(clampWeeks))
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

    /// The segmented-control label on the rhythm dial.
    var shortTitle: String {
        switch self {
        case .standard: return "Standard"
        case .early: return "Early"
        case .night: return "Late"
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

/// When a check-in would come: a usual meal time plus a grace period with
/// nothing logged. Onboarding draws these as the bells on the day dial.
enum CheckInSchedule {
    static let graceMin = 45

    static func minute(afterMeal mealMin: Int) -> Int {
        (mealMin + graceMin) % 1440
    }
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
