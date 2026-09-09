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

    func testLogMealRequestEncodesImagePayload() throws {
        let req = LogMealRequest(text: "burrito", image: .init(data: "YWJj", mediaType: "image/jpeg"))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
        )
        XCTAssertEqual(json["text"] as? String, "burrito")
        let image = try XCTUnwrap(json["image"] as? [String: Any])
        XCTAssertEqual(image["data"] as? String, "YWJj")
        XCTAssertEqual(image["mediaType"] as? String, "image/jpeg")
        XCTAssertNil(json["macros"])
    }

    func testLogMealResponseDecodesParsedBreakdown() throws {
        let json = """
        {
          "meal": { "id": "m_1", "kcal": 640, "proteinG": 41.2, "source": "PHOTO" },
          "parsed": {
            "items": [
              { "name": "Grilled chicken", "quantity": "1 breast", "kcal": 280, "proteinG": 32, "carbsG": 1, "fatG": 9 }
            ],
            "kcal": 640, "proteinG": 41.2, "carbsG": 60, "fatG": 18,
            "confidence": 0.62, "summary": "Chicken burrito bowl", "notes": "Assumed a medium portion."
          },
          "resolvedCheckInId": "ci_9"
        }
        """.data(using: .utf8)!
        let res = try JSONDecoder().decode(LogMealResponse.self, from: json)
        XCTAssertEqual(res.meal.source, "PHOTO")
        XCTAssertEqual(res.parsed?.summary, "Chicken burrito bowl")
        XCTAssertEqual(res.parsed?.items.first?.name, "Grilled chicken")
        XCTAssertEqual(res.resolvedCheckInId, "ci_9")
    }

    func testLogMealResponseDecodesWithoutParsed() throws {
        let json = #"{"meal":{"id":"m_2","kcal":300,"proteinG":10,"source":"PRESCRIPTION"},"parsed":null,"resolvedCheckInId":null}"#
            .data(using: .utf8)!
        let res = try JSONDecoder().decode(LogMealResponse.self, from: json)
        XCTAssertNil(res.parsed)
        XCTAssertNil(res.resolvedCheckInId)
    }

    func testConversationResponseDecodes() throws {
        let json = """
        {
          "messages": [
            { "role": "assistant", "content": "The last few days haven't gone to plan. Want to lower the target?", "at": "2026-09-09T12:00:00.000Z" },
            { "role": "user", "content": "yeah maybe", "at": null }
          ],
          "outcome": "ADJUST_PLAN",
          "resolved": true
        }
        """.data(using: .utf8)!
        let res = try JSONDecoder().decode(ConversationResponse.self, from: json)
        XCTAssertEqual(res.messages.count, 2)
        XCTAssertEqual(res.messages.first?.role, "assistant")
        XCTAssertNil(res.messages.last?.at)
        XCTAssertEqual(res.outcome, "ADJUST_PLAN")
        XCTAssertTrue(res.resolved)
    }

    @MainActor
    func testConversationOutcomeCopyMapsToPlainLanguage() {
        let vm = ConversationViewModel.previewed(resolved: true)
        XCTAssertEqual(vm.outcomeTitle, "Plan eased")
        XCTAssertEqual(vm.outcomeIcon, "slider.horizontal.3")
        XCTAssertEqual(vm.outcomeSummary, "We'll ease the plan. Fine-tune it in Settings.")
    }

    @MainActor
    func testLogMealCannotSubmitWithoutTextOrPhoto() {
        let vm = LogMealViewModel(api: AppEnvironment.preview().api)
        XCTAssertFalse(vm.canSubmit)
        vm.text = "  "
        XCTAssertFalse(vm.canSubmit)
        vm.text = "oatmeal"
        XCTAssertTrue(vm.canSubmit)
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
