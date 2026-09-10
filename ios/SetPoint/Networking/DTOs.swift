import Foundation
import UIKit

// Mirrors of the backend's JSON responses. The backend already emits camelCase,
// so no key-decoding strategy is needed.

struct AuthResponse: Decodable {
    let token: String
    let userId: String
}

struct HomeResponse: Decodable {
    let goal: String
    let mode: String
    let enforcementEnabled: Bool
    let ledger: Ledger
    let framing: Framing
    let managerNote: String
    let meals: [MealSummary]
    /// Usual breakfast / lunch / dinner minutes-from-midnight. Older payloads omit this.
    let mealTimes: MealTimesPayload?
    let activeCheckIn: ActiveCheckIn?

    var resolvedMealTimes: MealTimesPayload { mealTimes ?? .standard }

    struct Ledger: Decodable {
        let consumedKcal: Int
        let targetKcal: Int
        let remainingKcal: Int
        let consumedProteinG: Double
        let targetProteinG: Double?
        let remainingProteinG: Double?
        let mealsToday: Int
        let lastMealAt: String?
    }

    struct Framing: Decodable {
        let state: String        // "under" | "over" | "on_track"
        let accent: Bool
        let primaryCta: String?  // "log_meal" | nil
        let heroKcal: Int
    }

    struct ActiveCheckIn: Decodable, Identifiable {
        let id: String
        let tier: Int
        let status: String
        let message: String?
        let deferUntil: String?
        let prescription: Prescription?

        struct Prescription: Decodable {
            let id: String
            let totalKcal: Int
            let totalProteinG: Double
            let items: [Item]

            struct Item: Decodable, Identifiable {
                var id: String { name }
                let name: String
                let quantity: Double
                let kcal: Int
                let proteinG: Double
            }

            /// "2× Hard-boiled eggs + Banana"
            var summary: String {
                items
                    .map { $0.quantity > 1 ? "\(Int($0.quantity))× \($0.name)" : $0.name }
                    .joined(separator: " + ")
            }
        }
    }
}

/// A logged meal as it appears on Today and in a Week day detail.
struct MealSummary: Decodable, Identifiable, Hashable {
    let id: String
    let loggedAt: String
    let kcal: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let source: String
    let summary: String?
    /// Data URL when the meal was logged from a photo. Older payloads omit this.
    let photoUrl: String?
    let notes: String?
    let items: [Item]?
    let parseConfidence: Double?

    struct Item: Decodable, Hashable, Identifiable {
        var id: String { "\(name)|\(quantity)" }
        let name: String
        let quantity: String
        let kcal: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }

    var title: String {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Logged meal" : trimmed
    }

    var sourceLabel: String {
        switch source {
        case "PHOTO": return "Photo"
        case "TEXT": return "Text"
        case "PRESCRIPTION": return "Check-in"
        default: return "Logged"
        }
    }

    var photoImage: UIImage? {
        guard let photoUrl, photoUrl.hasPrefix("data:image") else { return nil }
        guard let comma = photoUrl.firstIndex(of: ",") else { return nil }
        let b64 = String(photoUrl[photoUrl.index(after: comma)...])
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }
}

struct MealsListResponse: Decodable {
    let date: String
    let meals: [MealSummary]
}

struct SettlementResponse: Decodable {
    let days: [Day]
    let today: Today
    let weekSummary: String
    let weightGoal: WeightGoal?

    struct Day: Decodable, Identifiable {
        var id: String { date }
        let date: String
        let kind: String
        let kcalConsumed: Int
        let kcalTarget: Int
        let summaryLine: String?
    }

    struct Today: Decodable {
        let date: String
        let kind: String
        let kcalConsumed: Int
        let kcalTarget: Int
    }

    /// Progress toward a weight goal (§5.1, M16). Present only for BULK/DIET.
    struct WeightGoal: Decodable {
        let goal: String
        let startWeightKg: Double?
        let targetWeightKg: Double?
        let currentWeightKg: Double?
        let changedKg: Double?
        let remainingKg: Double?
        let totalKg: Double?
        let fractionComplete: Double?
        let status: String        // ahead | on_pace | behind | reached | unknown
        let etaWeeks: Int?
        let lastWeighInAt: String?
        let needsWeighIn: Bool
    }
}

struct LogMealRequest: Encodable {
    var text: String?
    var image: ImagePayload?
    var macros: Macros?
    var prescriptionId: String?

    struct Macros: Encodable {
        let kcal: Int
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?
    }

    /// Base64 photo the backend feeds to the vision model (§5.5).
    struct ImagePayload: Encodable {
        let data: String
        let mediaType: String   // "image/jpeg" | "image/png" | "image/webp" | "image/gif"
    }
}

struct LogMealResponse: Decodable {
    let meal: Meal
    let parsed: Parsed?
    let resolvedCheckInId: String?

    struct Meal: Decodable {
        let id: String
        let kcal: Int
        let proteinG: Double
        let source: String
    }

    /// The AI breakdown, when text/photo was parsed. Nil for explicit-macro logs.
    struct Parsed: Decodable {
        let items: [Item]
        let kcal: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let confidence: Double
        let summary: String
        let notes: String?

        struct Item: Decodable, Identifiable, Equatable {
            var id: String { name + quantity }
            let name: String
            let quantity: String
            let kcal: Int
            let proteinG: Double
            let carbsG: Double
            let fatG: Double
        }
    }
}

struct MealCorrectionRequest: Encodable {
    let summary: String
    let items: [Item]

    struct Item: Encodable {
        let name: String
        let quantity: String
        let kcal: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }
}

struct MealCorrectionResponse: Decodable {
    let meal: MealSummary
}

struct ConversationRequest: Encodable {
    let message: String
}

/// The tier-3 "let's talk" exchange (§2). Bounded — the backend lands on an
/// `outcome` and then `resolved` is true and the composer closes.
struct ConversationResponse: Decodable {
    let messages: [ConversationMessage]
    let outcome: String        // "NONE" | "ADJUST_PLAN" | "PAUSE_CHECKINS" | "SUGGEST_PROFESSIONAL"
    let resolved: Bool
}

struct ConversationMessage: Decodable, Identifiable, Equatable {
    var id: String { role + (at ?? "") + content }
    let role: String           // "user" | "assistant"
    let content: String
    let at: String?
}

struct OnboardingRequest: Encodable {
    let goal: String
    let mode: String            // "BASIC" | "SMART"
    let timezone: String
    let sex: String
    let birthDate: String?      // "YYYY-MM-DD"
    let heightCm: Double?
    let weightKg: Double?
    let activityLevel: String
    var targetWeightKg: Double?
    var paceKgPerWeek: Double?
    let mealTimes: MinutesTriple
    let quietHours: MinutesRange
    let safety: Safety

    struct MinutesTriple: Encodable { let breakfastMin, lunchMin, dinnerMin: Int }
    struct MinutesRange: Encodable { let startMin, endMin: Int }

    struct Safety: Encodable {
        let medicalSupervisionRequired: Bool
        let scoff: Scoff
        let restrictions: [Restriction]
        let restrictionsFreeText: String?

        struct Scoff: Encodable {
            let makeSelfSick, lostControl, lostOneStone, believesFat, foodDominates: Bool
        }
        struct Restriction: Encodable { let label: String; let source: String? }
    }
}

struct OnboardingResponse: Decodable {
    let dailyKcalTarget: Int
    let dailyProteinTargetG: Int?
    let targetWeightKg: Double?
    let paceKgPerWeek: Double?
    let enforcementEnabled: Bool
    let enforcementDisabledReason: String?   // "MEDICAL_SUPERVISION" | "EATING_DISORDER_SCREEN" | nil
}

struct WeightLogRequest: Encodable {
    let weightKg: Double
    var measuredAt: String?
    var source: String?      // "manual" | "healthkit"
}

struct WeightLogResponse: Decodable {
    let goalReached: Bool
    let goal: String
    let dailyKcalTarget: Int
    let dailyProteinTargetG: Int?
    let entry: Entry

    struct Entry: Decodable {
        let id: String
        let weightKg: Double
        let measuredAt: String
        let source: String
    }
}

struct MealTimesPayload: Codable, Equatable {
    var breakfastMin: Int
    var lunchMin: Int
    var dinnerMin: Int

    static let standard = MealTimesPayload(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140)
}

struct QuietHoursPayload: Codable, Equatable {
    var startMin: Int
    var endMin: Int
}

struct SettingsResponse: Decodable {
    let goal: String
    let mode: String
    let timezone: String
    let dailyKcalTarget: Int
    let dailyProteinTargetG: Int?
    let targetWeightKg: Double?
    let paceKgPerWeek: Double
    let startWeightKg: Double?
    let currentWeightKg: Double?
    let mealTimes: MealTimesPayload
    let quietHours: QuietHoursPayload
    let checkInsPaused: Bool
    let restrictions: [Restriction]
    let enforcementEnabled: Bool
    let enforcementDisabledReason: String?

    struct Restriction: Decodable, Identifiable {
        var id: String { token }
        let label: String
        let token: String
        let source: String
    }
}

struct SettingsPatch: Encodable {
    var goal: String?
    var targetWeightKg: Double?
    var paceKgPerWeek: Double?
    var dailyKcalTarget: Int?
    var dailyProteinTargetG: Int?
    var mealTimes: MealTimesPayload?
    var quietHours: QuietHoursPayload?
    var checkInsPaused: Bool?
    var restrictions: [RestrictionInput]?

    struct RestrictionInput: Encodable {
        let label: String
        var source: String?
    }
}

struct DeleteAccountRequest: Encodable {
    let confirmation = "delete my account"
}

struct DeleteAccountResponse: Decodable {
    let deleted: Bool
    let appleTokenRevoked: Bool
}
