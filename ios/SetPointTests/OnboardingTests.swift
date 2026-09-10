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

    @MainActor
    func testStepGatingBlocksIncompleteSteps() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        XCTAssertEqual(vm.step, .welcome)
        XCTAssertTrue(vm.canAdvance)              // the intro gates nothing
        vm.advance()                             // → goal
        XCTAssertEqual(vm.step, .goal)
        XCTAssertFalse(vm.canAdvance)             // direction not chosen
        vm.draft.goal = .bulk
        XCTAssertTrue(vm.canAdvance)
        vm.advance()                             // → baseline
        XCTAssertEqual(vm.step, .you)
        XCTAssertFalse(vm.canAdvance)             // no height/weight
        vm.draft.heightCm = 175
        vm.draft.weightKg = 70
        XCTAssertFalse(vm.canAdvance)             // bulk needs a target weight
        vm.draft.targetWeightKg = 65
        XCTAssertFalse(vm.canAdvance)             // gain target must be above the baseline
        vm.draft.targetWeightKg = 76
        XCTAssertTrue(vm.canAdvance)
        vm.draft.goal = .maintain
        XCTAssertTrue(vm.canAdvance)              // maintain needs no target
    }

    @MainActor
    func testDailyRhythmRequiresChronologicalAnchors() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .checkins
        XCTAssertTrue(vm.canAdvance)

        vm.draft.lunchMin = vm.draft.breakfastMin
        XCTAssertFalse(vm.canAdvance)

        vm.draft.lunchMin = 780
        vm.draft.dinnerMin = 700
        XCTAssertFalse(vm.canAdvance)
    }

    @MainActor
    func testSafetyBeatGatesUntilScreenComplete() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        vm.step = .checkins
        XCTAssertTrue(vm.canAdvance)              // check-ins beat gates nothing
        vm.advance()                             // → safety
        XCTAssertEqual(vm.step, .safety)
        XCTAssertFalse(vm.canAdvance)             // SCOFF not answered
        vm.draft.scoff = ScoffAnswers(
            makeSelfSick: false, lostControl: false, lostOneStone: false,
            believesFat: false, foodDominates: false
        )
        XCTAssertTrue(vm.canAdvance)
    }

    @MainActor
    func testThreadIndexSkipsWelcomeAndOutcome() {
        let vm = OnboardingViewModel(api: AppEnvironment.preview().api, onComplete: {})
        XCTAssertNil(vm.threadIndex)              // welcome
        vm.step = .goal
        XCTAssertEqual(vm.threadIndex, 0)
        vm.step = .you
        XCTAssertEqual(vm.threadIndex, 1)
        vm.step = .review
        XCTAssertEqual(vm.threadIndex, 4)
        vm.step = .outcome
        XCTAssertNil(vm.threadIndex)
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
}
