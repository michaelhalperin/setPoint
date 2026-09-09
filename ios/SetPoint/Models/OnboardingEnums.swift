import Foundation

enum Goal: String, CaseIterable, Identifiable {
    case bulk = "BULK"
    case diet = "DIET"

    var id: String { rawValue }
    var title: String { self == .bulk ? "Gain" : "Lean out" }
    var blurb: String {
        self == .bulk
            ? "Put on size. The hard part is eating enough, consistently."
            : "Drop fat without under-eating. The floor matters more than the ceiling."
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
        case .sedentary: return "Mostly sitting"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }
}
