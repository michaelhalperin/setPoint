import SwiftUI
import XCTest
@testable import SetPoint

final class MotionTests: XCTestCase {
    func testAdaptiveFallsBackToCrossfadeUnderReduceMotion() {
        XCTAssertEqual(Motion.adaptive(Motion.standard, reduceMotion: true), .easeInOut(duration: 0.2))
    }

    func testAdaptiveKeepsSpringWhenMotionAllowed() {
        XCTAssertEqual(Motion.adaptive(Motion.snappy, reduceMotion: false), Motion.snappy)
    }
}

final class PaletteTests: XCTestCase {
    func testDayColorMapping() {
        XCTAssertEqual(Palette.day("ON_TRACK"), Palette.dayOnTrack)
        XCTAssertEqual(Palette.day("OVER"), Palette.dayOver)
        XCTAssertEqual(Palette.day("anything-else"), Palette.dayMissed)
    }
}
