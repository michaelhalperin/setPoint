import Foundation

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
    let activeCheckIn: ActiveCheckIn?

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

struct SettlementResponse: Decodable {
    let days: [Day]
    let today: Today
    let weekSummary: String

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
}

struct LogMealRequest: Encodable {
    var text: String?
    var macros: Macros?
    var prescriptionId: String?

    struct Macros: Encodable {
        let kcal: Int
        var proteinG: Double?
        var carbsG: Double?
        var fatG: Double?
    }
}

struct LogMealResponse: Decodable {
    let meal: Meal
    let resolvedCheckInId: String?

    struct Meal: Decodable {
        let id: String
        let kcal: Int
        let proteinG: Double
        let source: String
    }
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
    let enforcementEnabled: Bool
    let enforcementDisabledReason: String?   // "MEDICAL_SUPERVISION" | "EATING_DISORDER_SCREEN" | nil
}

struct MealTimesPayload: Codable, Equatable {
    var breakfastMin: Int
    var lunchMin: Int
    var dinnerMin: Int
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
