import Foundation
import Observation

struct ScoffAnswers: Codable {
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

struct OnboardingDraft: Codable {
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
    var preferredDurationWeeks: Int?

    var mealRhythmPreset: MealRhythmPreset = .standard
    var breakfastMin = 480    // 08:00
    var lunchMin = 780        // 13:00
    var dinnerMin = 1140      // 19:00
    var quietStartMin = 1380  // 23:00
    var quietEndMin = 420     // 07:00

    var restrictions: [String] = []
    var restrictionsFreeText = ""
    /// nil until the first safety card is answered.
    var medicalSupervisionRequired: Bool?
    var scoff = ScoffAnswers()

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    /// Fill in whatever Apple Health knows, leaving the rest as the user set it.
    mutating func apply(_ profile: HealthProfile) {
        if let height = profile.heightCm { heightCm = height }
        if let weight = profile.weightKg { weightKg = weight }
        if let birthDate = profile.birthDate { self.birthDate = birthDate }
        if let sex = profile.sex { self.sex = sex }
    }

    var isOldEnough: Bool { age >= OnboardingDraft.minimumAge }

    static let minimumAge = 16

    mutating func applyPreset(_ preset: MealRhythmPreset) {
        mealRhythmPreset = preset
        guard let times = preset.times else { return }
        breakfastMin = times.breakfast
        lunchMin = times.lunch
        dinnerMin = times.dinner
        applyDerivedQuietHours()
    }

    mutating func applyDerivedQuietHours() {
        let quiet = derivedQuietHours(breakfastMin: breakfastMin, dinnerMin: dinnerMin)
        quietStartMin = quiet.start
        quietEndMin = quiet.end
    }

    func toRequest() -> OnboardingRequest {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"

        let resolvedGoal = goal ?? .bulk
        let remaining: Double? = {
            guard resolvedGoal.hasWeightTarget, let current = weightKg, let target = targetWeightKg else { return nil }
            return WeightPace.remainingKg(goal: resolvedGoal, currentKg: current, targetKg: target)
        }()
        let resolved = WeightPace.resolve(
            goal: resolvedGoal,
            weightKg: weightKg,
            remainingKg: remaining,
            preferredWeeks: resolvedGoal.hasWeightTarget ? preferredDurationWeeks : nil,
            paceKgPerWeek: pace.kgPerWeek(for: resolvedGoal)
        )

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
            paceKgPerWeek: resolvedGoal.hasWeightTarget ? resolved.paceKgPerWeek : nil,
            preferredDurationWeeks: resolvedGoal.hasWeightTarget ? preferredDurationWeeks : nil,
            mealTimes: .init(breakfastMin: breakfastMin, lunchMin: lunchMin, dinnerMin: dinnerMin),
            quietHours: .init(startMin: quietStartMin, endMin: quietEndMin),
            safety: .init(
                medicalSupervisionRequired: medicalSupervisionRequired ?? false,
                medicalConditionAffectsEating: medicalSupervisionRequired,
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

/// The safety cards, in order: the medical question first, then SCOFF (§3).
enum SafetyQuestion: Int, CaseIterable {
    case medical, makeSelfSick, lostControl, lostOneStone, believesFat, foodDominates

    var text: String {
        switch self {
        case .medical: return "Do you have a medical condition that affects how you should eat — including eating under a doctor’s or dietitian’s care?"
        case .makeSelfSick: return "Do you make yourself sick because you feel uncomfortably full?"
        case .lostControl: return "Do you worry you have lost control over how much you eat?"
        case .lostOneStone: return "Have you recently lost more than 6 kg in a three-month period?"
        case .believesFat: return "Do you believe yourself to be fat when others say you are too thin?"
        case .foodDominates: return "Would you say that food dominates your life?"
        }
    }
}

@MainActor
@Observable
final class OnboardingViewModel {
    /// Setup after sign-in (the pitch lives in `WelcomeView`, before it). One
    /// decision per screen; `safety` submits, `reach` and `covered` come after.
    enum Step: Int, CaseIterable {
        case goal, about, target, rhythm, restrictions, safety
        case reach, covered
    }

    var step: Step = .goal
    var draft = OnboardingDraft()
    /// Which safety card is in front.
    var safetyIndex = 0
    var submitting = false
    var result: OnboardingResponse?
    var error: String?
    /// Set by the flow from the live notification status — nothing to ask when
    /// the user has already decided.
    var asksForNotifications = true

    private let api: APIClient
    let onComplete: @MainActor () -> Void

    /// Where in-progress answers are kept between launches. nil (tests,
    /// previews) keeps everything in memory.
    private let progressStore: UserDefaults?

    init(
        api: APIClient,
        progressStore: UserDefaults? = nil,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.api = api
        self.progressStore = progressStore
        self.onComplete = onComplete
        restoreProgress()
    }

    // MARK: Progress

    /// The steps that fill the ring on the Next button, for this goal.
    var progressSteps: [Step] {
        [.goal, .about, .target, .rhythm, .restrictions, .safety].filter { !shouldSkip($0) }
    }

    /// 0...1 — how full the ring is once the current step is done.
    var progress: Double {
        let steps = progressSteps
        guard let index = steps.firstIndex(of: step) else { return 1 }
        return Double(index + 1) / Double(steps.count)
    }

    var enforcementEnabled: Bool {
        result?.enforcementDisabledReason == nil
    }

    // MARK: Validation

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

    /// Whole weeks to the target at a safe pace, or nil without one.
    var etaWeeks: Int? {
        resolvedPace.preferredDurationWeeks
    }

    /// Why the entered timeframe won't be honored, or nil when it matches a safe pace.
    var durationMessage: String? {
        guard targetWeightMessage == nil,
              let preferred = draft.preferredDurationWeeks,
              let honest = etaWeeks,
              preferred != honest else { return nil }
        if preferred < honest {
            return "That's faster than a safe pace — about \(honest) weeks."
        }
        return "That's slower than I'll go — about \(honest) weeks."
    }

    private var remainingKg: Double? {
        guard let goal = draft.goal, goal.hasWeightTarget,
              let current = draft.weightKg, let target = draft.targetWeightKg else { return nil }
        return WeightPace.remainingKg(goal: goal, currentKg: current, targetKg: target)
    }

    private var resolvedPace: (paceKgPerWeek: Double, preferredDurationWeeks: Int?) {
        guard let goal = draft.goal else { return (0, nil) }
        return WeightPace.resolve(
            goal: goal,
            weightKg: draft.weightKg,
            remainingKg: remainingKg,
            preferredWeeks: draft.preferredDurationWeeks,
            paceKgPerWeek: draft.pace.kgPerWeek(for: goal)
        )
    }

    func applyPaceShortcut(_ pace: GoalPace) {
        draft.pace = pace
        guard let goal = draft.goal, let remaining = remainingKg else { return }
        let rate = WeightPace.clampKgPerWeek(goal: goal, weightKg: draft.weightKg, pace: pace.kgPerWeek(for: goal))
        draft.preferredDurationWeeks = WeightPace.etaWeeks(remainingKg: remaining, paceKgPerWeek: rate)
    }

    func setDurationWeeks(_ weeks: Int) {
        draft.preferredDurationWeeks = WeightPace.clampWeeks(weeks)
        guard let goal = draft.goal, let remaining = remainingKg, remaining > 0 else { return }
        draft.pace = GoalPace.closest(toKgPerWeek: remaining / Double(WeightPace.clampWeeks(weeks)), for: goal)
    }

    func proposeDurationIfNeeded() {
        guard draft.preferredDurationWeeks == nil, let remaining = remainingKg else { return }
        let rate = draft.pace.kgPerWeek(for: draft.goal ?? .bulk)
        draft.preferredDurationWeeks = WeightPace.etaWeeks(remainingKg: remaining, paceKgPerWeek: rate)
    }

    var mealAnchorsAreValid: Bool {
        draft.breakfastMin < draft.lunchMin && draft.lunchMin < draft.dinnerMin
    }

    var safetyComplete: Bool {
        draft.medicalSupervisionRequired != nil && draft.scoff.isComplete
    }

    func safetyAnswer(_ question: SafetyQuestion) -> Bool? {
        switch question {
        case .medical: return draft.medicalSupervisionRequired
        case .makeSelfSick: return draft.scoff.makeSelfSick
        case .lostControl: return draft.scoff.lostControl
        case .lostOneStone: return draft.scoff.lostOneStone
        case .believesFat: return draft.scoff.believesFat
        case .foodDominates: return draft.scoff.foodDominates
        }
    }

    // MARK: Navigation

    var canGoBack: Bool {
        guard !submitting else { return false }
        switch step {
        case .goal, .reach, .covered: return false
        default: return true
        }
    }

    var canAdvance: Bool {
        switch step {
        case .goal: return draft.goal != nil
        case .about: return draft.heightCm != nil && draft.weightKg != nil && draft.isOldEnough
        case .target: return targetWeightIsValid && draft.targetWeightKg != nil
        case .rhythm: return draft.mealRhythmPreset != .custom || mealAnchorsAreValid
        case .restrictions: return true
        case .safety: return safetyComplete && !submitting
        case .reach, .covered: return true
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
        case .safety:
            Task { await submit() }
        case .reach:
            step = .covered
        case .covered:
            onComplete()
        default:
            var next = step.rawValue + 1
            while let candidate = Step(rawValue: next), shouldSkip(candidate) { next += 1 }
            if let nextStep = Step(rawValue: next) { step = nextStep }
            saveProgress()
        }
    }

    func goBack() {
        if step == .safety, safetyIndex > 0 {
            safetyIndex -= 1
            saveProgress()
            return
        }
        var prev = step.rawValue - 1
        while let candidate = Step(rawValue: prev), shouldSkip(candidate) { prev -= 1 }
        if let prevStep = Step(rawValue: prev) { step = prevStep }
        saveProgress()
    }

    /// Answer the card in front; the last answer submits the plan.
    func answerSafety(_ value: Bool) {
        guard let question = SafetyQuestion(rawValue: safetyIndex) else { return }
        switch question {
        case .medical: draft.medicalSupervisionRequired = value
        case .makeSelfSick: draft.scoff.makeSelfSick = value
        case .lostControl: draft.scoff.lostControl = value
        case .lostOneStone: draft.scoff.lostOneStone = value
        case .believesFat: draft.scoff.believesFat = value
        case .foodDominates: draft.scoff.foodDominates = value
        }
        let answeredLast = safetyIndex == SafetyQuestion.allCases.count - 1
        if !answeredLast { safetyIndex += 1 }
        saveProgress()
        if answeredLast, safetyComplete {
            autoAdvance(from: .safety, after: 0.35)
        }
    }

    /// A single-choice screen advances itself shortly after the tap. Guards
    /// against firing if the user has already navigated away.
    func autoAdvance(from origin: Step, after seconds: Double = 0.32) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard self.step == origin else { return }
            advance()
        }
    }

    /// Where a saved plan goes next: straight to the payoff in quiet mode (no
    /// check-ins to deliver) or when notifications are already decided.
    func stepAfterSubmit(_ response: OnboardingResponse) -> Step {
        response.enforcementDisabledReason == nil && asksForNotifications ? .reach : .covered
    }

    private func submit() async {
        // Every safety answer is required — never submit a missing one as "no".
        guard !submitting, safetyComplete else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        #if DEBUG
        if previewOnly {
            let response = OnboardingResponse.preview
            result = response
            step = stepAfterSubmit(response)
            return
        }
        #endif
        do {
            let response: OnboardingResponse = try await api.post("/api/onboarding", draft.toRequest())
            result = response
            step = stepAfterSubmit(response)
            progressStore.map(Self.clearProgress)
        } catch {
            self.error = UserFacingError.message(for: error, fallback: "Couldn't save. Try again.")
            saveProgress()
        }
    }

    // MARK: Saved progress

    private struct Progress: Codable {
        static let version = 2
        var version = Progress.version
        var step: Int
        var safetyIndex: Int
        var draft: OnboardingDraft
    }

    private static let progressKey = "com.setpoint.app.onboarding.progress"

    /// Everything answered so far — goal, body, target, meal times, quiet
    /// hours, restrictions and safety answers — so a relaunch resumes exactly.
    private func saveProgress() {
        guard let progressStore, step != .reach, step != .covered else { return }
        let progress = Progress(step: step.rawValue, safetyIndex: safetyIndex, draft: draft)
        guard let data = try? JSONEncoder().encode(progress) else { return }
        progressStore.set(data, forKey: Self.progressKey)
    }

    private func restoreProgress() {
        guard let progressStore,
              let data = progressStore.data(forKey: Self.progressKey),
              let saved = try? JSONDecoder().decode(Progress.self, from: data),
              saved.version == Progress.version
        else { return }
        draft = saved.draft
        // Resume at the saved step, but never past one whose answers are missing.
        let target = Step(rawValue: saved.step) ?? .goal
        step = .goal
        while step.rawValue < target.rawValue, step.rawValue < Step.safety.rawValue, canAdvance {
            var next = step.rawValue + 1
            while let candidate = Step(rawValue: next), shouldSkip(candidate) { next += 1 }
            guard let nextStep = Step(rawValue: next) else { break }
            step = nextStep
        }
        if step == .safety {
            // Land on the first unanswered card.
            let firstOpen = SafetyQuestion.allCases.first { safetyAnswer($0) == nil }
            safetyIndex = firstOpen?.rawValue ?? min(saved.safetyIndex, SafetyQuestion.allCases.count - 1)
        }
    }

    static func clearProgress(in store: UserDefaults = .standard) {
        store.removeObject(forKey: progressKey)
        store.removeObject(forKey: "com.setpoint.app.onboarding.snapshot") // v1 format
    }

    #if DEBUG
    /// When true, Safety → next skips the API so a preview can walk the whole flow.
    var previewOnly = false

    static func previewed(
        at step: Step,
        onComplete: @escaping @MainActor () -> Void = {}
    ) -> OnboardingViewModel {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: onComplete)
        vm.previewOnly = true
        if step != .goal {
            vm.draft.goal = .bulk
            vm.draft.heightCm = 178
            vm.draft.weightKg = 74
            vm.draft.targetWeightKg = 80
            vm.draft.pace = .steady
        }
        if step == .safety { vm.safetyIndex = 2 }
        if step == .reach || step == .covered {
            vm.draft.medicalSupervisionRequired = false
            vm.draft.scoff = ScoffAnswers(
                makeSelfSick: false, lostControl: false, lostOneStone: false,
                believesFat: false, foodDominates: false
            )
            vm.result = .preview
        }
        vm.step = step
        return vm
    }
    #endif
}

#if DEBUG
extension OnboardingResponse {
    static let preview = OnboardingResponse(
        dailyKcalTarget: 3120, dailyProteinTargetG: 142,
        targetWeightKg: 80, paceKgPerWeek: 0.25,
        enforcementEnabled: true, enforcementDisabledReason: nil
    )
}
#endif

// Raw-value enums: Codable so an in-progress draft can be saved.
extension Goal: Codable {}
extension Sex: Codable {}
extension ActivityLevel: Codable {}
extension GoalPace: Codable {}
extension MealRhythmPreset: Codable {}
