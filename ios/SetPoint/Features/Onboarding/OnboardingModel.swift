import Foundation
import Observation

struct ScoffAnswers {
    var makeSelfSick: Bool?
    var lostControl: Bool?
    var lostOneStone: Bool?
    var believesFat: Bool?
    var foodDominates: Bool?

    var isComplete: Bool {
        makeSelfSick != nil && lostControl != nil && lostOneStone != nil
            && believesFat != nil && foodDominates != nil
    }
}

/// The healthy-weight floor for a diet target — BMI 18.5, mirroring the backend's
/// `minHealthyWeightKg`. SetPoint never helps anyone diet below it (§3).
enum HealthyWeight {
    static let bmiFloor = 18.5

    /// Lowest healthy target weight for a height, rounded up to 0.1 kg.
    static func minKg(heightCm: Double) -> Double {
        let meters = heightCm / 100
        return (bmiFloor * meters * meters * 10).rounded(.up) / 10
    }

    static func floorMessage(_ floor: Double) -> String {
        "The lowest target I'll set for your height is \(floor.formatted(.number.precision(.fractionLength(0 ... 1)))) kg."
    }
}

struct OnboardingDraft {
    var goal: Goal?
    var sex: Sex = .unspecified
    var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    var heightCm: Double?
    var weightKg: Double?
    var activityLevel: ActivityLevel = .moderate
    var hasWearable = false

    // Weight goal (M16) — nil / ignored for Maintain.
    var targetWeightKg: Double?
    var pace: GoalPace = .gentle

    var mealRhythmPreset: MealRhythmPreset = .standard
    var breakfastMin = 480    // 08:00
    var lunchMin = 780        // 13:00
    var dinnerMin = 1140      // 19:00
    var quietStartMin = 1380  // 23:00
    var quietEndMin = 420     // 07:00

    var restrictions: [String] = []
    var restrictionsFreeText = ""
    var medicalSupervisionRequired = false
    var scoff = ScoffAnswers()

    /// Explicit consent to the privacy policy + terms, checked on Review.
    var agreedToTerms = false

    func toRequest() -> OnboardingRequest {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"

        let resolvedGoal = goal ?? .bulk

        return OnboardingRequest(
            goal: resolvedGoal.rawValue,
            mode: hasWearable ? "SMART" : "BASIC",
            timezone: TimeZone.current.identifier,
            sex: sex.rawValue,
            birthDate: df.string(from: birthDate),
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel.rawValue,
            targetWeightKg: resolvedGoal.hasWeightTarget ? targetWeightKg : nil,
            paceKgPerWeek: resolvedGoal.hasWeightTarget ? pace.kgPerWeek(for: resolvedGoal) : nil,
            mealTimes: .init(breakfastMin: breakfastMin, lunchMin: lunchMin, dinnerMin: dinnerMin),
            quietHours: .init(startMin: quietStartMin, endMin: quietEndMin),
            safety: .init(
                medicalSupervisionRequired: medicalSupervisionRequired,
                scoff: .init(
                    makeSelfSick: scoff.makeSelfSick ?? false,
                    lostControl: scoff.lostControl ?? false,
                    lostOneStone: scoff.lostOneStone ?? false,
                    believesFat: scoff.believesFat ?? false,
                    foodDominates: scoff.foodDominates ?? false
                ),
                restrictions: restrictions.map { .init(label: $0, source: nil) },
                restrictionsFreeText: restrictionsFreeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : restrictionsFreeText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    /// The intake as many small beats rather than a few dense forms — each
    /// screen is one decision. `hook`/`demo` sell before asking for anything;
    /// `outcome` delivers. Everything between is threaded with a progress bar.
    enum Step: Int, CaseIterable {
        case hook, demo
        case goal, vitals, birthdate, sex, activity, target, rhythm, wearable, restrictions, medical, safety
        case review, outcome
    }

    var step: Step = .hook
    var draft = OnboardingDraft()
    var submitting = false
    var result: OnboardingResponse?
    var error: String?

    private let api: APIClient
    let onComplete: @MainActor () -> Void

    init(api: APIClient, onComplete: @escaping @MainActor () -> Void) {
        self.api = api
        self.onComplete = onComplete
    }

    /// Beats that carry the progress thread (the sell and the payoff don't).
    static let threadedSteps: [Step] = [
        .goal, .vitals, .birthdate, .sex, .activity, .target, .rhythm, .wearable, .restrictions, .medical, .safety, .review,
    ]

    /// 0-based position of `step` within the thread, or nil if it isn't threaded.
    var threadIndex: Int? {
        Self.threadedSteps.firstIndex(of: step)
    }

    var targetWeightIsValid: Bool {
        guard let goal = draft.goal else { return false }
        guard goal.hasWeightTarget else { return true }
        guard draft.weightKg != nil, draft.targetWeightKg != nil else { return false }
        return targetWeightMessage == nil
    }

    /// Why the entered target won't work, or nil when it's fine (or not entered yet).
    var targetWeightMessage: String? {
        guard let goal = draft.goal, goal.hasWeightTarget,
              let current = draft.weightKg, let target = draft.targetWeightKg else { return nil }
        switch goal {
        case .bulk:
            return target > current ? nil : "Above current weight."
        case .diet:
            let floor = draft.heightCm.map { HealthyWeight.minKg(heightCm: $0) }
            if let floor, current <= floor {
                return "At your height, I won't set a lower target. Maintain is the better fit."
            }
            if target >= current { return "Below current weight." }
            if let floor, target < floor { return HealthyWeight.floorMessage(floor) }
            return nil
        case .maintain:
            return nil
        }
    }

    var mealAnchorsAreValid: Bool {
        draft.breakfastMin < draft.lunchMin && draft.lunchMin < draft.dinnerMin
    }

    var canGoBack: Bool {
        step != .hook && step != .outcome && !submitting
    }

    var canAdvance: Bool {
        switch step {
        case .hook, .demo: return true
        case .goal: return draft.goal != nil
        case .vitals: return draft.heightCm != nil && draft.weightKg != nil
        case .birthdate, .sex, .activity, .wearable, .medical: return true
        case .target: return targetWeightIsValid && draft.targetWeightKg != nil
        case .rhythm: return draft.mealRhythmPreset != .custom || mealAnchorsAreValid
        case .restrictions: return true
        case .safety: return draft.scoff.isComplete
        case .review: return !submitting && draft.agreedToTerms
        case .outcome: return true
        }
    }

    var primaryTitle: String {
        switch step {
        case .hook: return "Let's go"
        case .review: return submitting ? "Building…" : "Build plan"
        case .outcome: return "Start"
        default: return "Continue"
        }
    }

    var stepTitle: String? {
        switch step {
        case .goal: return "Direction"
        case .vitals: return "Body"
        case .birthdate: return "Birthday"
        case .sex, .activity: return "About you"
        case .target: return "Target"
        case .rhythm: return "Rhythm"
        case .wearable: return "Signal"
        case .restrictions: return "Boundaries"
        case .medical: return "Medical"
        case .safety: return "Safety check"
        case .review: return "Ready"
        default: return nil
        }
    }

    /// `.target` only applies to a goal with a weight target — Maintain skips it.
    private func shouldSkip(_ step: Step) -> Bool {
        switch step {
        case .target: return draft.goal?.hasWeightTarget != true
        default: return false
        }
    }

    func advance() {
        switch step {
        case .review:
            Task { await submit() }
        case .outcome:
            onComplete()
        default:
            var next = step.rawValue + 1
            while let candidate = Step(rawValue: next), shouldSkip(candidate) { next += 1 }
            if let nextStep = Step(rawValue: next) { step = nextStep }
        }
    }

    func goBack() {
        var prev = step.rawValue - 1
        while let candidate = Step(rawValue: prev), shouldSkip(candidate) { prev -= 1 }
        if let prevStep = Step(rawValue: prev) { step = prevStep }
    }

    /// A single-choice screen (goal, sex, activity, a rhythm preset, wearable,
    /// medical) advances itself shortly after the tap — no separate Continue
    /// needed. Guards against firing if the user has already navigated away.
    func autoAdvance(from origin: Step, after seconds: Double = 0.32) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard self.step == origin else { return }
            advance()
        }
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        #if DEBUG
        if previewOnly {
            result = OnboardingResponse(
                dailyKcalTarget: 3120, dailyProteinTargetG: 142,
                targetWeightKg: 85, paceKgPerWeek: 0.25,
                enforcementEnabled: true, enforcementDisabledReason: nil
            )
            step = .outcome
            return
        }
        #endif
        do {
            let response: OnboardingResponse = try await api.post("/api/onboarding", draft.toRequest())
            result = response
            step = .outcome
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't save. Try again.")
        }
    }

    #if DEBUG
    /// When true, Review → Start skips the API so a preview can walk the whole flow.
    var previewOnly = false

    static func previewed(
        at step: Step,
        onComplete: @escaping @MainActor () -> Void = {}
    ) -> OnboardingViewModel {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: onComplete)
        vm.previewOnly = true
        vm.draft.goal = .bulk
        vm.draft.heightCm = 182
        vm.draft.weightKg = 79
        vm.draft.targetWeightKg = 85
        vm.draft.pace = .steady
        vm.draft.restrictions = ["Dairy", "Peanuts"]
        vm.draft.scoff = ScoffAnswers(
            makeSelfSick: false, lostControl: false, lostOneStone: false,
            believesFat: false, foodDominates: false
        )
        if step == .outcome {
            vm.result = OnboardingResponse(
                dailyKcalTarget: 3120, dailyProteinTargetG: 142,
                targetWeightKg: 85, paceKgPerWeek: 0.25,
                enforcementEnabled: true, enforcementDisabledReason: nil
            )
        }
        vm.step = step
        return vm
    }
    #endif
}
