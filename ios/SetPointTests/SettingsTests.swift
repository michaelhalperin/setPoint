import XCTest
@testable import SetPoint

final class SettingsTests: XCTestCase {
    func testSettingsResponseDecodes() throws {
        let json = """
        {
          "goal": "DIET", "mode": "BASIC", "timezone": "Europe/London",
          "dailyKcalTarget": 2100, "dailyProteinTargetG": null,
          "targetWeightKg": 74, "paceKgPerWeek": 0.5, "startWeightKg": 80, "currentWeightKg": 77.5,
          "mealTimes": { "breakfastMin": 480, "lunchMin": 780, "dinnerMin": 1140 },
          "quietHours": { "startMin": 1380, "endMin": 420 },
          "checkInsPaused": true,
          "restrictions": [{ "label": "Peanuts", "token": "peanut", "source": "ALLERGY" }],
          "enforcementEnabled": false, "enforcementDisabledReason": "EATING_DISORDER_SCREEN"
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SettingsResponse.self, from: json)
        XCTAssertNil(s.dailyProteinTargetG)
        XCTAssertEqual(s.targetWeightKg, 74)
        XCTAssertEqual(s.paceKgPerWeek, 0.5)
        XCTAssertEqual(s.currentWeightKg, 77.5)
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
          "weekSummary": "One day in.",
          "weightGoal": {
            "goal": "DIET", "startWeightKg": 80, "targetWeightKg": 74, "currentWeightKg": 77.5,
            "changedKg": 2.5, "remainingKg": 3.5, "totalKg": 6, "fractionComplete": 0.42,
            "status": "on_pace", "etaWeeks": 7, "lastWeighInAt": "2026-09-01T08:00:00.000Z", "needsWeighIn": false
          }
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SettlementResponse.self, from: json)
        XCTAssertEqual(s.days.count, 1)
        XCTAssertEqual(s.today.kind, "ON_TRACK")
        XCTAssertEqual(s.weekSummary, "One day in.")
        XCTAssertEqual(s.weightGoal?.status, "on_pace")
        XCTAssertEqual(s.weightGoal?.remainingKg, 3.5)
        XCTAssertEqual(s.weightGoal?.etaWeeks, 7)
    }

    func testSettlementResponseDecodesWithoutWeightGoal() throws {
        let json = """
        { "days": [], "today": { "date": "2026-09-02", "kind": "MISSED", "kcalConsumed": 0, "kcalTarget": 2500 }, "weekSummary": "x" }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SettlementResponse.self, from: json)
        XCTAssertNil(s.weightGoal)
    }

    func testWeightLogRequestEncodes() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(WeightLogRequest(weightKg: 78.4))) as? [String: Any]
        )
        XCTAssertEqual(json["weightKg"] as? Double, 78.4)
        XCTAssertNil(json["source"])
    }
}
