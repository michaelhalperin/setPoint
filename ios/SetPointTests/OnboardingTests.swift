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
        XCTAssertFalse(vm.canAdvance)             // goal not chosen
        vm.draft.goal = .bulk
        XCTAssertTrue(vm.canAdvance)
        vm.advance()                             // → aboutYou
        XCTAssertEqual(vm.step, .aboutYou)
        XCTAssertFalse(vm.canAdvance)             // no height/weight
        vm.draft.heightCm = 175
        vm.draft.weightKg = 70
        XCTAssertTrue(vm.canAdvance)
    }
}
