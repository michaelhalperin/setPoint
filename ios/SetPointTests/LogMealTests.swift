import XCTest
@testable import SetPoint

@MainActor
final class LogMealTests: XCTestCase {
    private func makeVM() -> LogMealViewModel {
        LogMealViewModel(api: AppEnvironment.preview().api)
    }

    func testCannotSubmitWithNoInput() {
        XCTAssertFalse(makeVM().canSubmit)
    }

    func testCanSubmitOnceThereIsText() {
        let vm = makeVM()
        vm.text = "  chicken burrito bowl  "
        XCTAssertTrue(vm.canSubmit)
    }

    func testCannotSubmitWhileParsing() {
        let vm = LogMealViewModel.previewed(.parsing, submittedPrompt: "burrito")
        XCTAssertFalse(vm.canSubmit)
        XCTAssertEqual(vm.submittedPrompt, "burrito")
        XCTAssertEqual(vm.text, "", "the field clears when the meal is sent into the day")
    }

    func testResetFromFailureKeepsWhatTheUserTyped() {
        let vm = LogMealViewModel.previewed(.failed("no signal"), text: "burrito")
        vm.reset()
        XCTAssertEqual(vm.phase, .compose)
        XCTAssertEqual(vm.text, "burrito", "the compose input must survive a failed parse")
    }

    func testClearAfterSuccessWipesTheComposer() {
        let vm = LogMealViewModel.previewed(LogMealViewModel.sampleLogged, text: "burrito", submittedPrompt: "burrito")
        vm.clearAfterSuccess()
        XCTAssertEqual(vm.phase, .compose)
        XCTAssertEqual(vm.text, "")
        XCTAssertEqual(vm.submittedPrompt, "")
        XCTAssertFalse(vm.confirmingPhoto)
        XCTAssertNil(vm.photo)
    }

    func testPhotoParseWaitsForConfirm() {
        let vm = LogMealViewModel.samplePhotoConfirm
        XCTAssertTrue(vm.confirmingPhoto)
        if case .logged = vm.phase {} else { XCTFail("expected a parsed photo log") }
        vm.keepLogged()
        XCTAssertFalse(vm.confirmingPhoto)
        XCTAssertEqual(vm.phase, .compose)
    }

    func testEndConfirmKeepsTheLoggedMealForTheMorph() {
        let vm = LogMealViewModel.samplePhotoConfirm
        vm.endConfirm()
        XCTAssertFalse(vm.confirmingPhoto)
        if case .logged = vm.phase {} else { XCTFail("logged state must survive until the card lands") }
    }
}
