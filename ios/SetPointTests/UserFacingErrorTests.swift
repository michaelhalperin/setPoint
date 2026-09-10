import XCTest
@testable import SetPoint

final class UserFacingErrorTests: XCTestCase {
    func testHttpErrorsNeverSurfaceServerCopy() {
        let raw = APIError.http(
            status: 400,
            message: "Body cannot be empty when content-type is set to application/json"
        )
        let shown = UserFacingError.message(for: raw, fallback: "Couldn't remove that meal. Try again.")
        XCTAssertEqual(shown, "Couldn't remove that meal. Try again.")
        XCTAssertFalse(shown.localizedCaseInsensitiveContains("content-type"))
        XCTAssertFalse(shown.localizedCaseInsensitiveContains("json"))
    }

    func testServer500IsPlainLanguage() {
        let raw = APIError.http(status: 500, message: "Internal Server Error")
        let shown = UserFacingError.message(for: raw)
        XCTAssertEqual(shown, "The server had a problem. Try again in a bit.")
        XCTAssertFalse(shown.localizedCaseInsensitiveContains("internal"))
    }

    func testAPIErrorDescriptionNeverLeaksFrameworkCopy() {
        let raw = APIError.http(status: 415, message: "Body cannot be empty when content-type is set to application/json")
        XCTAssertEqual(raw.errorDescription, UserFacingError.generic)
        XCTAssertFalse(raw.localizedDescription.contains("application/json"))
    }

    func testTransportIsConnectionCopy() {
        let shown = UserFacingError.message(for: APIError.transport(URLError(.notConnectedToInternet)))
        XCTAssertEqual(shown, UserFacingError.unreachable)
    }

    func testUnknownErrorsUseFallbackNotLocalizedDescription() {
        struct Weird: Error {}
        let shown = UserFacingError.message(for: Weird(), fallback: "Couldn't log that meal. Try again.")
        XCTAssertEqual(shown, "Couldn't log that meal. Try again.")
    }
}
