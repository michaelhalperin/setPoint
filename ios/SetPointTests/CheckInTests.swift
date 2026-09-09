import XCTest
@testable import SetPoint

final class CheckInTests: XCTestCase {
    func testLogFromPrescriptionEncodesOnlyPrescriptionId() throws {
        let req = LogMealRequest(text: nil, macros: nil, prescriptionId: "rx_42")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
        )
        XCTAssertEqual(json["prescriptionId"] as? String, "rx_42")
        XCTAssertNil(json["text"])
        XCTAssertNil(json["macros"])
    }

    func testActiveCheckInDecodesWithoutPrescription() throws {
        let json = """
        {
          "id": "ci_9", "tier": 1, "status": "PENDING",
          "message": "Time to eat.", "deferUntil": null, "prescription": null
        }
        """.data(using: .utf8)!
        let ci = try JSONDecoder().decode(HomeResponse.ActiveCheckIn.self, from: json)
        XCTAssertEqual(ci.tier, 1)
        XCTAssertNil(ci.prescription)
    }
}
