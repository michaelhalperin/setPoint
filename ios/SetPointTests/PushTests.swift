import ActivityKit
import XCTest
@testable import SetPoint

final class PushTests: XCTestCase {
    func testDeepLinkParsesCheckIn() {
        XCTAssertEqual(DeepLink(url: URL(string: "setpoint://check-in/ci_42")!), .checkIn(id: "ci_42"))
        XCTAssertEqual(DeepLink(url: URL(string: "setpoint://check-in/ci_42/")!), .checkIn(id: "ci_42"))
    }

    func testDeepLinkRejectsOtherURLs() {
        XCTAssertNil(DeepLink(url: URL(string: "setpoint://check-in/")!))
        XCTAssertNil(DeepLink(url: URL(string: "setpoint://home")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://set-point-backend.vercel.app/check-in/x")!))
    }

    func testActivityContentStateRoundTrips() throws {
        let state = CheckInActivityAttributes.ContentState(
            title: "You're past your usual meal gap.",
            detail: "2× Hard-boiled eggs + Banana",
            deepLink: "setpoint://check-in/ci_1"
        )
        let decoded = try JSONDecoder().decode(
            CheckInActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
    }

    func testPrescriptionSummary() throws {
        let json = """
        { "id": "rx", "totalKcal": 620, "totalProteinG": 48, "items": [
          { "name": "Rotisserie chicken", "quantity": 1, "kcal": 260, "proteinG": 35 },
          { "name": "White rice", "quantity": 2, "kcal": 410, "proteinG": 9 }
        ] }
        """.data(using: .utf8)!
        let rx = try JSONDecoder().decode(HomeResponse.ActiveCheckIn.Prescription.self, from: json)
        XCTAssertEqual(rx.summary, "Rotisserie chicken + 2× White rice")
    }
}
