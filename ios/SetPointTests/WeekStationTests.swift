import XCTest
@testable import SetPoint

final class WeekStationTests: XCTestCase {
    func testStationsRunChronologicallyWithTodayLast() {
        let stations = SettlementResponse.sample.weekStations
        XCTAssertEqual(stations.map(\.date), [
            "2026-09-02", "2026-09-03", "2026-09-04",
            "2026-09-05", "2026-09-06", "2026-09-07",
            "2026-09-08",
        ])
        XCTAssertEqual(stations.filter(\.isToday).count, 1)
        XCTAssertEqual(stations.last?.isToday, true)
        XCTAssertEqual(stations.last?.kcalConsumed, 1180)
        XCTAssertNil(stations.last?.summaryLine)
    }

    func testEmptyWeekStillHasToday() {
        let stations = SettlementResponse.sampleEmpty.weekStations
        XCTAssertEqual(stations.count, 1)
        XCTAssertEqual(stations[0].isToday, true)
        XCTAssertEqual(stations[0].title, "Today")
        XCTAssertEqual(SettlementResponse.sampleEmpty.settledOnTrackCount, 0)
    }

    func testOnTrackCountIgnoresToday() {
        XCTAssertEqual(SettlementResponse.sample.settledOnTrackCount, 3)
    }

    func testFillClampsOverTarget() {
        let over = SettlementResponse.sample.weekStations.first { $0.kind == "OVER" }
        XCTAssertEqual(over?.fill, 1)
        let missed = SettlementResponse.sample.weekStations.first { $0.kind == "MISSED" }
        XCTAssertEqual(missed?.fill, 0)
        let under = SettlementResponse.sample.weekStations.first { $0.kind == "UNDER" && !$0.isToday }
        XCTAssertEqual(under?.fill ?? 0, 2260.0 / 3000.0, accuracy: 0.0001)
    }

    func testDoesNotDuplicateTodayIfAlreadyInDays() {
        let response = SettlementResponse(
            days: [
                .init(date: "2026-09-08", kind: "ON_TRACK", kcalConsumed: 3000, kcalTarget: 3000, summaryLine: "Done."),
            ],
            today: .init(date: "2026-09-08", kind: "UNDER", kcalConsumed: 100, kcalTarget: 3000),
            weekSummary: "One day.",
            weightGoal: nil
        )
        XCTAssertEqual(response.weekStations.count, 1)
        XCTAssertFalse(response.weekStations[0].isToday)
        XCTAssertEqual(response.weekStations[0].kcalConsumed, 3000)
    }
}
