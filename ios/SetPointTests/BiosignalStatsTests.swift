import XCTest
@testable import SetPoint

final class BiosignalStatsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ value: Double, hoursAgo h: Double) -> BiosignalSample {
        BiosignalSample(value: value, date: now.addingTimeInterval(-h * 3600))
    }

    func testBaselineNeedsEnoughHistoricalSamples() {
        let few = (0 ..< 4).map { sample(50, hoursAgo: 24 + Double($0) * 24) }
        XCTAssertNil(BiosignalStats.baseline(few, now: now))
    }

    func testBaselineExcludesTheRecentWindow() throws {
        // 10 stable historical readings + a wild recent one
        var samples = (1 ... 10).map { sample(50, hoursAgo: 24 * Double($0)) }
        samples.append(sample(999, hoursAgo: 1))
        let base = try XCTUnwrap(BiosignalStats.baseline(samples, now: now))
        XCTAssertEqual(base.mean, 50, accuracy: 0.001) // the 999 didn't move it
    }

    func testDeviationIsNegativeWhenHRVDrops() {
        var samples = (1 ... 14).map { sample(60, hoursAgo: 24 * Double($0)) }
        samples.append(sample(58, hoursAgo: 26))
        samples.append(sample(62, hoursAgo: 30))
        // recent window: a suppressed reading
        samples.append(sample(40, hoursAgo: 2))
        let z = BiosignalStats.zScore(samples, now: now)
        XCTAssertNotNil(z)
        XCTAssertLessThan(z!, 0)
    }

    func testDeviationIsAboutZeroWhenSteady() {
        let samples = (0 ... 20).map { sample(55 + Double($0 % 3), hoursAgo: 6 * Double($0)) }
        let z = BiosignalStats.zScore(samples, now: now)
        XCTAssertNotNil(z)
        XCTAssertLessThan(abs(z!), 2)
    }

    func testNoRecentSamplesYieldsNil() {
        let old = (1 ... 10).map { sample(50, hoursAgo: 48 * Double($0)) }
        guard let base = BiosignalStats.baseline(old, now: now) else { return XCTFail() }
        XCTAssertNil(BiosignalStats.deviation(recent: old, now: now, baseline: base))
    }
}
