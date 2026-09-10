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
        let vm = LogMealViewModel.previewed(.parsing, text: "burrito")
        XCTAssertFalse(vm.canSubmit)
    }

    func testResetFromFailureKeepsWhatTheUserTyped() {
        let vm = LogMealViewModel.previewed(.failed("no signal"), text: "burrito")
        vm.reset()
        XCTAssertEqual(vm.phase, .compose)
        XCTAssertEqual(vm.text, "burrito", "the compose input must survive a failed parse")
    }
}
