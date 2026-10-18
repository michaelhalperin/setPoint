import XCTest
@testable import SetPoint

final class CalendarWeekTests: XCTestCase {
    private let weekJSON = """
    {
      "enabled": true, "leadMin": 45, "minBlockMin": 60, "workdaysOnly": true,
      "includeAllDay": false, "countFree": false, "today": "2026-09-14",
      "days": [{
        "date": "2026-09-15", "weekday": 2,
        "blocks": [{ "startMin": 720, "endMin": 930, "allDay": false, "counts": true }],
        "meals": [{
          "slot": "lunch", "usualMin": 780, "atMin": 675, "moved": true, "reason": "lead",
          "kept": false, "canKeep": true, "earlyMin": 675,
          "busy": { "startMin": 720, "endMin": 930 },
          "status": "upcoming", "loggedMin": null, "kcal": null
        }]
      }],
      "movedCount": 1,
      "next": {
        "date": "2026-09-15", "slot": "lunch", "usualMin": 780, "atMin": 675, "earlyMin": 675,
        "kept": false, "reason": "lead", "busy": { "startMin": 720, "endMin": 930 }
      }
    }
    """.data(using: .utf8)!

    func testDecodesWeek() throws {
        let week = try JSONDecoder().decode(CalendarWeekResponse.self, from: weekJSON)
        XCTAssertEqual(week.movedCount, 1)
        XCTAssertEqual(week.day("2026-09-15")?.meals.first?.atMin, 675)
        XCTAssertEqual(week.next?.busy.endMin, 930)
    }

    func testKeepMovesLunchBackAndUndoes() throws {
        let week = try JSONDecoder().decode(CalendarWeekResponse.self, from: weekJSON)
        let kept = week.withKeep(date: "2026-09-15", slot: "lunch", keep: true)
        XCTAssertEqual(kept.movedCount, 0)
        XCTAssertEqual(kept.day("2026-09-15")?.meals.first?.atMin, 780)
        XCTAssertEqual(kept.next?.kept, true)
        let undone = kept.withKeep(date: "2026-09-15", slot: "lunch", keep: false)
        XCTAssertEqual(undone, week)
    }

    func testClockAndDurations() {
        XCTAssertEqual(CalendarClock.hm(675), "11:15")
        XCTAssertEqual(CalendarClock.range(720, 930), "12:00–15:30")
        XCTAssertEqual(CalendarClock.duration(45), "45 min")
        XCTAssertEqual(CalendarClock.duration(60), "1 hour")
        XCTAssertEqual(CalendarClock.duration(210), "3½ hours")
        XCTAssertEqual(CalendarClock.duration(75), "1 h 15 min")
    }

    func testWhyCopyMatchesTheHeadsUp() {
        let busy = CalendarWeekResponse.Span(startMin: 720, endMin: 930)
        XCTAssertEqual(
            CalendarCopy.why(eventName: "Client workshop", slot: "lunch", busy: busy, earlyMin: 675, usualMin: 780, reason: "lead", kept: false, leadMin: 45),
            "Client workshop starts 12:00 and runs 3½ hours. Your heads-up is 45 min before it starts, so lunch moves to 11:15."
        )
        XCTAssertTrue(
            CalendarCopy.why(eventName: nil, slot: "lunch", busy: busy, earlyMin: 690, usualMin: 780, reason: "floor", kept: false, leadMin: 45)
                .contains("never closer than 90 min after breakfast")
        )
        XCTAssertEqual(CalendarCopy.keepTitle(slot: "lunch", usualMin: 780), "Keep lunch at 13:00")
        XCTAssertEqual(CalendarCopy.headline(slot: "lunch", busy: busy, kept: false, usualMin: 780), "Busy 12:00–15:30, so lunch is earlier.")
    }

    func testEventVerdicts() {
        func verdict(_ duration: Int, allDay: Bool = false, weekday: Int = 2) -> CalendarRules.Verdict {
            CalendarRules.verdict(durationMin: duration, allDay: allDay, weekday: weekday, minBlockMin: 60, workdaysOnly: true, includeAllDay: false)
        }
        XCTAssertEqual(verdict(15), .tooShort)
        XCTAssertEqual(verdict(210), .counts)
        XCTAssertEqual(verdict(1440, allDay: true), .allDayOff)
        XCTAssertEqual(verdict(210, weekday: 6), .weekend)
        XCTAssertEqual(CalendarRules.label(.tooShort), "Too short to count")
    }

    func testPreviewSummary() {
        let preview = CalendarPreviewResponse(movedCount: 2, moved: [
            .init(date: "2026-09-15", weekday: 2, slot: "lunch", usualMin: 780, atMin: 675),
            .init(date: "2026-09-17", weekday: 4, slot: "dinner", usualMin: 1140, atMin: 1035),
        ])
        XCTAssertEqual(preview.summary, "Tue lunch, Thu dinner")
    }

    func testSettingsPatchSendsCountFree() throws {
        let data = try JSONEncoder().encode(SettingsPatch(calendar: .init(countFree: true)))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""countFree":true"#))
    }
}
