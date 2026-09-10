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
}
