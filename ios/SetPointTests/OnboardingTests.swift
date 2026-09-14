import XCTest
@testable import SetPoint

final class OnboardingTests: XCTestCase {
    private func encoded(_ req: OnboardingRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(req)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDraftEncodesToBackendShape() throws {
        var draft = OnboardingDraft()
        draft.goal = .bulk
        draft.hasWearable = true
        draft.heightCm = 182
        draft.weightKg = 79.5
        draft.birthDate = ISO8601DateFormatter().date(from: "1994-05-01T00:00:00Z")!
        draft.restrictions = ["Peanuts", "Dairy"]

        let json = try encoded(draft.toRequest())
        XCTAssertEqual(json["goal"] as? String, "BULK")
        XCTAssertEqual(json["mode"] as? String, "SMART")
        XCTAssertEqual(json["birthDate"] as? String, "1994-05-01")
        XCTAssertEqual(json["heightCm"] as? Double, 182)

        let safety = try XCTUnwrap(json["safety"] as? [String: Any])
        XCTAssertEqual(safety["medicalSupervisionRequired"] as? Bool, false)
        let restrictions = try XCTUnwrap(safety["restrictions"] as? [[String: Any]])
        XCTAssertEqual(restrictions.map { $0["label"] as? String }, ["Peanuts", "Dairy"])
        let scoff = try XCTUnwrap(safety["scoff"] as? [String: Any])
        XCTAssertEqual(scoff["makeSelfSick"] as? Bool, false)
    }

    func testFreeTextOmittedWhenBlank() throws {
        var draft = OnboardingDraft()
        draft.goal = .diet
        draft.restrictionsFreeText = "   "
        let safety = try XCTUnwrap(try encoded(draft.toRequest())["safety"] as? [String: Any])
        XCTAssertNil(safety["restrictionsFreeText"])
    }

    func testScoffCompleteness() {
        var s = ScoffAnswers()
        XCTAssertFalse(s.isComplete)
        s.makeSelfSick = false
        s.lostControl = false
        s.lostOneStone = false
        s.believesFat = false
        XCTAssertFalse(s.isComplete)
        s.foodDominates = true
        XCTAssertTrue(s.isComplete)
    }

    // MARK: Step gating — one decision per screen

    @MainActor
    private func makeModel() -> OnboardingViewModel {
        OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
    }

    @MainActor
    func testSetupStartsAtTheGoalWithNoWayBack() {
        let vm = makeModel()
        XCTAssertEqual(vm.step, .goal)
        XCTAssertFalse(vm.canGoBack) // the pitch lives before sign-in, not behind this
    }

    @MainActor
    func testGoalGatesUntilChosen() {
        let vm = makeModel()
        XCTAssertFalse(vm.canAdvance)
        vm.draft.goal = .bulk
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testAboutRequiresHeightAndWeight() {
        let vm = makeModel()
        vm.step = .about
        XCTAssertFalse(vm.canAdvance)
        vm.draft.heightCm = 175
        XCTAssertFalse(vm.canAdvance)
        vm.draft.weightKg = 70
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testTargetStepGatesOnAValidWeight() {
        let vm = makeModel()
        vm.step = .target
        vm.draft.goal = .bulk
        vm.draft.weightKg = 70
        XCTAssertFalse(vm.canAdvance)             // no target yet
        vm.draft.targetWeightKg = 65
        XCTAssertFalse(vm.canAdvance)              // gain target must be above the baseline
        vm.draft.targetWeightKg = 76
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testMaintainSkipsTheTargetStepBothWays() {
        let vm = makeModel()
        vm.draft.goal = .maintain
        vm.step = .about
        vm.advance()
        XCTAssertEqual(vm.step, .rhythm)          // .target skipped going forward
        vm.goBack()
        XCTAssertEqual(vm.step, .about)           // and skipped coming back
    }

    @MainActor
    func testGainKeepsTheTargetStep() {
        let vm = makeModel()
        vm.draft.goal = .bulk
        vm.step = .about
        vm.advance()
        XCTAssertEqual(vm.step, .target)
        vm.advance()
        XCTAssertEqual(vm.step, .rhythm)
    }

    @MainActor
    func testProgressRingCountsOnlyTheStepsThisGoalSees() {
        let vm = makeModel()
        vm.draft.goal = .bulk
        XCTAssertEqual(vm.progress, 1.0 / 6, accuracy: 0.001)
        vm.step = .safety
        XCTAssertEqual(vm.progress, 1, accuracy: 0.001)

        vm.draft.goal = .maintain
        vm.step = .goal
        XCTAssertEqual(vm.progress, 1.0 / 5, accuracy: 0.001)
    }

    @MainActor
    func testRhythmGatesOnlyWhenCustomIsInvalid() {
        let vm = makeModel()
        vm.step = .rhythm
        XCTAssertTrue(vm.canAdvance)               // default preset is always valid

        vm.draft.mealRhythmPreset = .custom
        vm.draft.lunchMin = vm.draft.breakfastMin
        XCTAssertFalse(vm.canAdvance)

        vm.draft.lunchMin = 780
        vm.draft.dinnerMin = 700
        XCTAssertFalse(vm.canAdvance)

        vm.draft.dinnerMin = 1140
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testApplyingAPresetSetsTimesAndQuietHours() {
        var draft = OnboardingDraft()
        draft.applyPreset(.night)
        XCTAssertEqual([draft.breakfastMin, draft.lunchMin, draft.dinnerMin], [600, 900, 1260])
        XCTAssertEqual(draft.quietStartMin, 60)
        XCTAssertEqual(draft.quietEndMin, 540)
    }

    @MainActor
    func testSafetyCardsWalkMedicalThenScoff() {
        let vm = makeModel()
        vm.step = .safety
        XCTAssertFalse(vm.canAdvance)

        vm.answerSafety(true)
        XCTAssertEqual(vm.draft.medicalSupervisionRequired, true)
        XCTAssertEqual(vm.safetyIndex, 1)

        for _ in 0 ..< 4 { vm.answerSafety(false) }
        XCTAssertEqual(vm.safetyIndex, 5)
        XCTAssertFalse(vm.canAdvance)              // the last SCOFF card is still open

        vm.goBack()
        XCTAssertEqual(vm.step, .safety)           // back steps through the cards first
        XCTAssertEqual(vm.safetyIndex, 4)
        vm.safetyIndex = 5

        vm.draft.scoff.foodDominates = true
        XCTAssertTrue(vm.safetyComplete)
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testQuietModeAndDecidedNotificationsSkipTheAsk() {
        let vm = makeModel()
        let on = OnboardingResponse(dailyKcalTarget: 2400, dailyProteinTargetG: 120, targetWeightKg: nil,
                                    paceKgPerWeek: nil, enforcementEnabled: true, enforcementDisabledReason: nil)
        let quiet = OnboardingResponse(dailyKcalTarget: 2000, dailyProteinTargetG: nil, targetWeightKg: nil,
                                       paceKgPerWeek: nil, enforcementEnabled: false,
                                       enforcementDisabledReason: "EATING_DISORDER_SCREEN")
        XCTAssertEqual(vm.stepAfterSubmit(on), .reach)
        XCTAssertEqual(vm.stepAfterSubmit(quiet), .covered)
        vm.asksForNotifications = false
        XCTAssertEqual(vm.stepAfterSubmit(on), .covered)
    }

    @MainActor
    func testEtaUsesThePace() {
        let vm = makeModel()
        vm.draft.goal = .bulk
        vm.draft.weightKg = 74
        vm.draft.targetWeightKg = 80
        vm.draft.pace = .steady                     // 0.25 kg/wk for a gain
        XCTAssertEqual(vm.etaWeeks, 24)
        vm.draft.goal = .maintain
        XCTAssertNil(vm.etaWeeks)
    }

    func testHealthProfileFillsOnlyWhatItKnows() {
        var draft = OnboardingDraft()
        draft.heightCm = 180
        draft.sex = .female
        draft.apply(HealthProfile(heightCm: nil, weightKg: 72.4, birthDate: nil, sex: nil))
        XCTAssertEqual(draft.heightCm, 180)
        XCTAssertEqual(draft.weightKg, 72.4)
        XCTAssertEqual(draft.sex, .female)
    }

    func testCheckInTimesFollowTheMeals() {
        XCTAssertEqual(CheckInSchedule.minute(afterMeal: 780), 825)
        XCTAssertEqual(CheckInSchedule.minute(afterMeal: 1420), 25) // wraps past midnight
    }

    @MainActor
    func testAutoAdvanceOnlyFiresIfStillOnTheOriginatingStep() async {
        let vm = makeModel()
        vm.draft.goal = .bulk
        vm.autoAdvance(from: .goal, after: 0.05)
        vm.step = .about // navigate away before the timer fires
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(vm.step, .about) // unchanged — the stale auto-advance was ignored
    }

    @MainActor
    func testGoalStepSendsTargetAndPace() throws {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.draft.goal = .diet
        vm.draft.weightKg = 82
        vm.draft.targetWeightKg = 76
        vm.draft.pace = .steady
        let json = try encoded(vm.draft.toRequest())
        XCTAssertEqual(json["targetWeightKg"] as? Double, 76)
        XCTAssertEqual(json["paceKgPerWeek"] as? Double, GoalPace.steady.kgPerWeek(for: .diet))

        vm.draft.goal = .maintain
        XCTAssertNil(try encoded(vm.draft.toRequest())["targetWeightKg"])
    }

    // MARK: Meal rhythm presets

    func testPresetsCarryTheirOwnTimes() {
        XCTAssertEqual(MealRhythmPreset.standard.times.map { [$0.breakfast, $0.lunch, $0.dinner] }, [480, 780, 1140])
        XCTAssertNil(MealRhythmPreset.custom.times)
    }

    func testQuietHoursAreDerivedFromMealTimes() {
        let standard = derivedQuietHours(breakfastMin: 480, dinnerMin: 1140)
        XCTAssertEqual(standard.start, 1380) // 23:00 — matches the old fixed default
        XCTAssertEqual(standard.end, 420)    // 07:00

        let nightOwl = derivedQuietHours(breakfastMin: 600, dinnerMin: 1260)
        XCTAssertEqual(nightOwl.start, 60)   // wraps past midnight: 21:00 + 4h = 01:00
        XCTAssertEqual(nightOwl.end, 540)    // 09:00
    }

    func testClosestPresetMatchesExactTimesOnly() {
        XCTAssertEqual(MealRhythmPreset.closest(breakfast: 480, lunch: 780, dinner: 1140), .standard)
        XCTAssertEqual(MealRhythmPreset.closest(breakfast: 500, lunch: 780, dinner: 1140), .custom)
    }
}
