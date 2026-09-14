import SwiftUI
import XCTest
@testable import SetPoint

final class MassUnitTests: XCTestCase {
    func testConvertsAtTheEdgesOnly() {
        XCTAssertEqual(MassUnit.lb.fromKg(70), 154.32, accuracy: 0.01)
        XCTAssertEqual(MassUnit.lb.toKg(154.32), 70, accuracy: 0.01)
        XCTAssertEqual(MassUnit.kg.fromKg(70), 70)
        XCTAssertEqual(MassUnit.lb.formatKg(70), "154.3 lb")
        XCTAssertEqual(MassUnit.kg.formatKg(70), "70.0 kg")
    }

    func testEditingInPoundsStoresKilograms() {
        var stored = 70.0
        let kg = Binding(get: { stored }, set: { stored = $0 })
        MassUnit.lb.binding(kg: kg).wrappedValue = 160
        XCTAssertEqual(stored, 72.57, accuracy: 0.01)
    }

    func testNudgeMovesByWholeUnitsOfTheChosenUnit() {
        let kg = MassUnit.lb.nudge(kg: 70, by: 1) // 154.3 lb → 155 lb
        XCTAssertEqual(MassUnit.lb.fromKg(kg), 155, accuracy: 0.001)
        XCTAssertEqual(MassUnit.kg.nudge(kg: 70.4, by: -1), 69)
    }

    func testRangesStayInsideTheKilogramBounds() {
        let range = MassUnit.lb.range(kg: 35 ... 250)
        XCTAssertGreaterThanOrEqual(MassUnit.lb.toKg(range.lowerBound), 35)
        XCTAssertLessThanOrEqual(MassUnit.lb.toKg(range.upperBound), 250)
    }
}
