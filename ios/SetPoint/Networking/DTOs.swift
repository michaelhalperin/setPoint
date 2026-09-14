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
    /// Today's meal-time slots, where now sits, and pace. Older payloads omit it.
    var day: Day? = nil
    /// The check-in coming if nothing is logged. Nil in quiet mode, while paused,
    /// while one is open, or once the day is covered.
    var nextCheckIn: NextCheckIn? = nil
    /// Surface a weigh-in near the plan card when the last one is stale.
    var needsWeighIn: Bool? = nil
    var busyBlocks: [BusyBlock]? = nil
    var movedSlots: [MovedSlot]? = nil
    var training: Training? = nil

    struct BusyBlock: Decodable, Equatable {
        let startMin: Int
        let endMin: Int
    }

    struct MovedSlot: Decodable, Equatable {
        let slot: String
        let fromMin: Int
        let toMin: Int
    }

    struct Training: Decodable, Equatable {
        var bumpKcal: Int
        var addCalories: Bool
        var workouts: [Workout]
        var refuelUntilMin: Int? = nil

        struct Workout: Decodable, Equatable, Identifiable {
            let id: String
            let kind: String
            let source: String
            let startMin: Int
            let durationMin: Int
            var activeKcal: Int? = nil
        }
    }

    struct NextCheckIn: Decodable, Equatable {
        let slot: String      // "breakfast" | "lunch" | "dinner"
        let mealMin: Int
        let dueMin: Int
        let overdue: Bool
    }

    var resolvedMealTimes: MealTimesPayload { mealTimes ?? .standard }

    /// Quiet hours, minutes from midnight. Older payloads omit them; the default
    /// matches onboarding's derived window.
    var quietHours: QuietHoursPayload? = nil
    var resolvedQuietHours: QuietHoursPayload {
        if let quietHours { return quietHours }
        let times = resolvedMealTimes
        let derived = derivedQuietHours(breakfastMin: times.breakfastMin, dinnerMin: times.dinnerMin)
        return QuietHoursPayload(startMin: derived.start, endMin: derived.end)
    }

    /// The shape of today, decided by the backend: breakfast / lunch / dinner
    /// slots (logged, due now, missed, upcoming), now, and pace.
    struct Day: Decodable, Equatable {
        let nowMin: Int
        let slots: [Slot]
        /// Nil in quiet mode — no pace or "behind" framing at all.
        let pace: Pace?

        struct Slot: Decodable, Equatable, Identifiable {
            let slot: String      // "breakfast" | "lunch" | "dinner"
            let atMin: Int
            let state: String     // "logged" | "now" | "missed" | "upcoming"
            let mealIds: [String]
            let kcal: Int

            var id: String { slot }
        }

        struct Pace: Decodable, Equatable {
            let expectedByNowKcal: Int
            let behindKcal: Int
            let status: String    // "behind" | "on_pace" | "ahead"
            let next: Next?
        }

        struct Next: Decodable, Equatable {
            let slot: String
            let atMin: Int
            let suggestedKcal: Int
        }
    }

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
        /// The meal it's about; nil for a tier-3 conversation.
        var slot: String? = nil
        var kind: String? = nil

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
                    .map { item in
                        let qty = item.quantity
                        if qty > 1 { return "\(Int(qty)) × \(item.name)" }
                        return item.name
                    }
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
    /// A signed https URL for a stored photo, or a legacy inline data URL. Nil without a photo.
    let photoUrl: String?
    let notes: String?
    let items: [Item]?
    let parseConfidence: Double?
    var parseQuality: String? = nil

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
        case "SAVED": return "My meal"
        case "BARCODE": return "Scanned"
        default: return "Logged"
        }
    }

    var isScanned: Bool { source == "BARCODE" }

    /// A stored photo's signed URL — load it through `MealPhotoCache`.
    var remotePhotoURL: URL? {
        guard let photoUrl, photoUrl.hasPrefix("https://") else { return nil }
        return URL(string: photoUrl)
    }

    /// A legacy inline (data URL) photo, decoded.
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

/// `POST /api/settings/target-review`. Accept carries the target the user saw.
struct TargetReviewDecision: Encodable {
    let action: String
    let proposedKcal: Int?
}

struct SettlementResponse: Decodable {
    let days: [Day]
    let today: Today
    let weekSummary: String
    let weightGoal: WeightGoal?
    /// How each meal went this week. Older payloads omit it.
    var record: Record? = nil
    var targetReview: TargetReview? = nil

    struct TargetReview: Decodable {
        let previousKcal: Int
        let proposedKcal: Int
        let deltaKcal: Int
        let reason: String
        let weighInCount: Int
        let trendKgPerWeek: Double
        let windowStart: String
        let windowEnd: String
    }

    /// Per day and meal: on time, after a check-in, missed, or still open — and
    /// one late-meal pattern the app can fix in a tap.
    struct Record: Decodable {
        let days: [RecordDay]
        let onTime: Int
        let afterCheckIn: Int
        let missed: Int
        let checkIns: Int
        let pattern: Pattern?

        struct RecordDay: Decodable, Identifiable {
            var id: String { date }
            let date: String
            /// breakfast, lunch, dinner: "on_time" | "after_check_in" | "missed" | "open"
            let slots: [String]
        }

        struct Pattern: Decodable, Equatable {
            let slot: String
            let lateDays: Int
            let ofDays: Int
            let currentMin: Int
            let suggestedMin: Int
        }
    }

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
    /// Log a named plate as-is — never AI-parsed.
    var savedMealId: String? = nil
    /// Cached / Open Food Facts barcode. Pair with `servings`.
    var barcode: String? = nil
    var servings: Double? = nil
    /// ISO timestamp for a meal eaten earlier (a missed meal time). Omitted = now.
    var loggedAt: String?
    /// Idempotency key for this log attempt (the offline queue retries with it).
    var clientId: String?

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

struct StartTalkResponse: Decodable {
    let checkInId: String
}

struct ConversationConfirmResponse: Decodable {
    let outcome: String
    let resolved: Bool
}

/// The tier-3 "let's talk" exchange (§2). Bounded — the backend lands on an
/// `outcome` and then `resolved` is true and the composer closes.
struct ConversationResponse: Decodable {
    let messages: [ConversationMessage]
    let outcome: String        // "NONE" | "DELAY_CHECKINS" | "EASE_TARGET" | "PAUSE_CHECKINS" | "SUGGEST_PROFESSIONAL"
    let resolved: Bool
    var pendingProposal: PlanProposal? = nil

    struct PlanProposal: Decodable, Equatable {
        let kind: String
        let title: String
        let summary: String
    }
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
    var preferredDurationWeeks: Int?
    let mealTimes: MinutesTriple
    let quietHours: MinutesRange
    let safety: Safety

    struct MinutesTriple: Encodable { let breakfastMin, lunchMin, dinnerMin: Int }
    struct MinutesRange: Encodable { let startMin, endMin: Int }

    struct Safety: Encodable {
        let medicalSupervisionRequired: Bool
        let medicalConditionAffectsEating: Bool?
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
    var preferredDurationWeeks: Int? = nil
    let enforcementEnabled: Bool
    let enforcementDisabledReason: String?   // "MEDICAL_SUPERVISION" | "EATING_DISORDER_SCREEN" | nil
}

struct WeightLogRequest: Encodable {
    let weightKg: Double
    var measuredAt: String?
    var source: String?      // "manual" | "healthkit"
}

struct WeightHistoryResponse: Decodable {
    let entries: [Entry]

    struct Entry: Decodable, Identifiable {
        let id: String
        let weightKg: Double
        let measuredAt: String
    }
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

struct WeekendMealTimesPayload: Codable, Equatable {
    var breakfastMin: Int?
    var lunchMin: Int?
    var dinnerMin: Int?

    static let empty = WeekendMealTimesPayload(breakfastMin: nil, lunchMin: nil, dinnerMin: nil)

    func resolved(from weekdays: MealTimesPayload) -> MealTimesPayload {
        MealTimesPayload(
            breakfastMin: breakfastMin ?? weekdays.breakfastMin,
            lunchMin: lunchMin ?? weekdays.lunchMin,
            dinnerMin: dinnerMin ?? weekdays.dinnerMin
        )
    }

    subscript(slot: MealSlot) -> Int? {
        get {
            switch slot {
            case .breakfast: return breakfastMin
            case .lunch: return lunchMin
            case .dinner: return dinnerMin
            }
        }
        set {
            switch slot {
            case .breakfast: breakfastMin = newValue
            case .lunch: lunchMin = newValue
            case .dinner: dinnerMin = newValue
            }
        }
    }
}

struct WeekendSuggestion: Decodable, Equatable {
    let breakfastMin: Int
    let lateByMin: Int
}

/// JS `getDay` bitmask: bit 0 = Sunday … bit 6 = Saturday. Default Sat+Sun.
enum WeekendDays {
    static let `default` = 0b1000001
    static let bitsInDisplayOrder = [1, 2, 3, 4, 5, 6, 0]
    static let labels = ["M", "T", "W", "T", "F", "S", "S"]
    static let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func contains(_ mask: Int, weekday: Int) -> Bool {
        ((mask >> (weekday % 7)) & 1) == 1
    }

    static func toggling(_ mask: Int, weekday: Int) -> Int {
        let next = mask ^ (1 << (weekday % 7))
        return next == 0 ? mask : next
    }

    static func summary(_ mask: Int) -> String {
        let picked = zip(bitsInDisplayOrder, names).compactMap { contains(mask, weekday: $0.0) ? $0.1 : nil }
        if picked.isEmpty { return "No days" }
        return picked.joined(separator: ", ")
    }
}

struct TrainingSettingsPayload: Codable, Equatable {
    var addCalories: Bool?
    var preWorkoutNudgeMin: Int?
}

struct WorkoutSyncPayload: Encodable {
    let workouts: [Item]

    struct Item: Encodable {
        let source: String
        let kind: String
        let start: Date
        let durationMin: Int
        var activeKcal: Int? = nil
        var clientId: String? = nil
    }
}

struct TrainingWeekResponse: Decodable {
    let addCalories: Bool
    var preWorkoutNudgeMin: Int? = nil
    let fueledWell: Fueled
    let days: [Day]
    let today: Today

    struct Fueled: Decodable {
        let good: Int
        let total: Int
    }

    struct Day: Decodable, Identifiable {
        var id: String { date }
        let date: String
        let bumpKcal: Int
        let rest: Bool
        let workouts: [Session]
    }

    struct Session: Decodable, Identifiable {
        let id: String
        let kind: String
        let source: String
        let start: String
        let startMin: Int
        let durationMin: Int
        var activeKcal: Int? = nil
    }

    struct Today: Decodable {
        let baseKcal: Int
        let bumpKcal: Int
        let targetKcal: Int
        let workouts: [Session]
        let dinnerMin: Int
        let timeline: [TimelineEvent]
    }

    struct TimelineEvent: Decodable, Identifiable {
        var id: String { "\(kind)-\(atMin)" }
        let kind: String
        let atMin: Int
        let label: String
        var nudge: Bool? = nil
    }
}

struct CalendarSettingsPayload: Codable, Equatable {
    var enabled: Bool?
    var leadMin: Int?
    var minBlockMin: Int?
    var workdaysOnly: Bool?
    var includeAllDay: Bool?
}

struct HealthWritePayload: Codable, Equatable {
    var energy: Bool
    var protein: Bool
    var carbs: Bool
    var fat: Bool
    var bodyMass: Bool

    static let `default` = HealthWritePayload(
        energy: true,
        protein: true,
        carbs: true,
        fat: true,
        bodyMass: false
    )
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
    var preferredDurationWeeks: Int? = nil
    let startWeightKg: Double?
    let currentWeightKg: Double?
    let mealTimes: MealTimesPayload
    var weekendMealTimes: WeekendMealTimesPayload? = nil
    var weekendDays: Int? = nil
    var weekendSuggestion: WeekendSuggestion? = nil
    let quietHours: QuietHoursPayload
    let checkInsPaused: Bool
    let restrictions: [Restriction]
    let enforcementEnabled: Bool
    let enforcementDisabledReason: String?
    var heightCm: Double? = nil
    /// Lowest diet target the backend accepts for this height (BMI 18.5).
    var minHealthyWeightKg: Double? = nil
    var pantryTokens: [String]? = nil
    var dislikedFoods: [String]? = nil
    var prepTimeMaxMin: Int? = nil
    var healthWrite: HealthWritePayload? = nil
    var calendar: CalendarSettingsPayload? = nil
    var training: TrainingSettingsPayload? = nil

    struct Restriction: Decodable, Identifiable {
        var id: String { token }
        let label: String
        let token: String
        let source: String
    }
}

struct SettingsPatch: Encodable {
    var goal: String?
    var mode: String?
    var targetWeightKg: Double?
    var paceKgPerWeek: Double?
    var preferredDurationWeeks: Int?
    var dailyKcalTarget: Int?
    var dailyProteinTargetG: Int?
    var mealTimes: MealTimesPayload?
    var weekendMealTimes: WeekendMealTimesPayload?
    var weekendDays: Int?
    var quietHours: QuietHoursPayload?
    var checkInsPaused: Bool?
    var restrictions: [RestrictionInput]?
    var pantryTokens: [String]?
    var dislikedFoods: [String]?
    var prepTimeMaxMin: Int?
    var healthWrite: HealthWritePayload?
    var calendar: CalendarSettingsPayload?
    var training: TrainingSettingsPayload?

    struct RestrictionInput: Encodable {
        let label: String
        var source: String?
    }
}

struct SavedMealsResponse: Decodable {
    let meals: [SavedMeal]
    var slot: String? = nil
}

struct SavedMeal: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let items: [MealSummary.Item]
    let kcal: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let suggestSlot: String?
    let useInCheckIns: Bool
    let lastUsedAt: String?
    let useCount: Int
    let suggested: Bool
}

struct SavedMealWrite: Encodable {
    let name: String
    let items: [MealCorrectionRequest.Item]
    let suggestSlot: String?
    let useInCheckIns: Bool
}

struct SavedMealResponse: Decodable {
    let meal: SavedMeal
}

struct BarcodeFood: Decodable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let brand: String?
    let servingG: Double?
    let kcal100g: Double
    let proteinG100g: Double
    let carbsG100g: Double
    let fatG100g: Double
    let fetchedAt: String

    func portion(servings: Double) -> (grams: Double, kcal: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        let serving = (servingG ?? 0) > 0 ? (servingG ?? 100) : 100
        let grams = serving * servings
        let factor = grams / 100
        return (
            grams,
            Int((kcal100g * factor).rounded()),
            (proteinG100g * factor * 10).rounded() / 10,
            (carbsG100g * factor * 10).rounded() / 10,
            (fatG100g * factor * 10).rounded() / 10
        )
    }
}

struct BarcodeFoodResponse: Decodable {
    let food: BarcodeFood
}

struct DeleteAccountRequest: Encodable {
    let confirmation = "delete my account"
}

struct DeleteAccountResponse: Decodable {
    let deleted: Bool
    let appleTokenRevoked: Bool
}
