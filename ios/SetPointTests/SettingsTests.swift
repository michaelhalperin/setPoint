import XCTest
@testable import SetPoint

final class SettingsTests: XCTestCase {
    func testSettingsResponseDecodes() throws {
        let json = """
        {
          "goal": "DIET", "mode": "BASIC", "timezone": "Europe/London",
          "dailyKcalTarget": 2100, "dailyProteinTargetG": null,
          "mealTimes": { "breakfastMin": 480, "lunchMin": 780, "dinnerMin": 1140 },
          "quietHours": { "startMin": 1380, "endMin": 420 },
          "checkInsPaused": true,
          "restrictions": [{ "label": "Peanuts", "token": "peanut", "source": "ALLERGY" }],
          "enforcementEnabled": false, "enforcementDisabledReason": "EATING_DISORDER_SCREEN"
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SettingsResponse.self, from: json)
        XCTAssertNil(s.dailyProteinTargetG)
        XCTAssertTrue(s.checkInsPaused)
        XCTAssertEqual(s.mealTimes, MealTimesPayload(breakfastMin: 480, lunchMin: 780, dinnerMin: 1140))
        XCTAssertEqual(s.restrictions.first?.label, "Peanuts")
        XCTAssertFalse(s.enforcementEnabled)
    }

    func testSettingsPatchOmitsNilFields() throws {
        let patch = SettingsPatch(checkInsPaused: true)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any]
        )
        XCTAssertEqual(json["checkInsPaused"] as? Bool, true)
        XCTAssertNil(json["goal"])
        XCTAssertNil(json["mealTimes"])
    }

    func testDeleteAccountRequestCarriesTheConfirmationPhrase() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(DeleteAccountRequest())) as? [String: Any]
        )
        XCTAssertEqual(json["confirmation"] as? String, "delete my account")
    }

    func testSettlementResponseDecodes() throws {
        let json = """
        {
          "days": [
            { "date": "2026-09-01", "kind": "UNDER", "kcalConsumed": 2200, "kcalTarget": 3000, "summaryLine": "Short." }
          ],
          "today": { "date": "2026-09-02", "kind": "ON_TRACK", "kcalConsumed": 2900, "kcalTarget": 3000 },
          "weekSummary": "One day in."
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SettlementResponse.self, from: json)
        XCTAssertEqual(s.days.count, 1)
        XCTAssertEqual(s.today.kind, "ON_TRACK")
        XCTAssertEqual(s.weekSummary, "One day in.")
    }
}
