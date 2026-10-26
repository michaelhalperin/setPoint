import XCTest
@testable import SetPoint

/// Photo Fix tags stay inside the photo, and the Meal times label names the
/// days the person picked as their weekend.
final class PhotoChipTests: XCTestCase {
    private let width: CGFloat = 400

    private func edges(spotX: CGFloat, chip: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let dx = MealCorrectionEditor.chipDx(spotX: spotX, chipWidth: chip, containerWidth: width)
        let center = spotX * width + dx
        return (center - chip / 2, center + chip / 2)
    }

    func testShortTagInTheMiddleDoesNotMove() {
        XCTAssertEqual(MealCorrectionEditor.chipDx(spotX: 0.5, chipWidth: 120, containerWidth: width), 0)
    }

    func testWideTagsStayInsideTheMargins() {
        let margin = MealCorrectionEditor.chipMargin
        let widest = width - 2 * margin
        for spotX in [0.24, 0.32, 0.5, 0.66, 0.76] as [CGFloat] {
            for chip in [180, 260, 320, widest] as [CGFloat] {
                let e = edges(spotX: spotX, chip: chip)
                XCTAssertGreaterThanOrEqual(e.left, margin - 0.001, "spot \(spotX), chip \(chip)")
                XCTAssertLessThanOrEqual(e.right, width - margin + 0.001, "spot \(spotX), chip \(chip)")
            }
        }
    }

    func testWeekendSpanFollowsThePickedDays() {
        let sat = 6, sun = 0, fri = 5
        let satSun = (1 << sat) | (1 << sun)
        let friSat = (1 << fri) | (1 << sat)

        XCTAssertEqual(WeekendDays.span(satSun, weekends: true).components(separatedBy: " · ").count, 2)
        XCTAssertTrue(WeekendDays.span(satSun, weekends: false).contains(" – "))
        XCTAssertTrue(WeekendDays.span(friSat, weekends: true).contains(WeekendDays.name(fri)))
        XCTAssertFalse(WeekendDays.span(friSat, weekends: true).contains(WeekendDays.name(sun)))
    }
}
