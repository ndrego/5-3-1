import XCTest
@testable import FiveThreeOne

final class PlateCalculatorTests: XCTestCase {

    func testStandardPlate_135() {
        let result = PlateCalculator.calculate(totalWeight: 135)
        XCTAssertEqual(result.plates, [45])
        XCTAssertEqual(result.totalWeight, 135)
        XCTAssertTrue(result.isExact)
    }

    func testStandardPlate_225() {
        let result = PlateCalculator.calculate(totalWeight: 225)
        XCTAssertEqual(result.plates, [45, 45])
        XCTAssertEqual(result.totalWeight, 225)
        XCTAssertTrue(result.isExact)
    }

    func testEmptyBar() {
        let result = PlateCalculator.calculate(totalWeight: 45)
        XCTAssertTrue(result.plates.isEmpty)
        XCTAssertEqual(result.totalWeight, 45)
        XCTAssertTrue(result.isExact)
    }

    func testBelowBarWeight() {
        let result = PlateCalculator.calculate(totalWeight: 40, barWeight: 45)
        XCTAssertTrue(result.plates.isEmpty)
        XCTAssertEqual(result.totalWeight, 45)
        XCTAssertFalse(result.isExact)
    }

    func testMixedPlates_215() {
        let result = PlateCalculator.calculate(totalWeight: 215)
        // 215 - 45 = 170 per both sides, 85 per side
        // 45 + 35 + 5 = 85
        XCTAssertEqual(result.plates, [45, 35, 5])
        XCTAssertEqual(result.totalWeight, 215)
        XCTAssertTrue(result.isExact)
    }

    func testFractionalPlates() {
        let result = PlateCalculator.calculate(totalWeight: 50)
        // 50 - 45 = 5, per side = 2.5
        XCTAssertEqual(result.plates, [2.5])
        XCTAssertEqual(result.totalWeight, 50)
        XCTAssertTrue(result.isExact)
    }

    func testCustomBarWeight() {
        let result = PlateCalculator.calculate(totalWeight: 95, barWeight: 35)
        // 95 - 35 = 60, per side = 30 -> 25 + 5
        XCTAssertEqual(result.plates, [25, 5])
        XCTAssertEqual(result.totalWeight, 95)
        XCTAssertTrue(result.isExact)
    }

    func testImpossibleWeight() {
        // 47.5 - 45 = 2.5, per side = 1.25 — no plate matches
        let result = PlateCalculator.calculate(totalWeight: 47.5, barWeight: 45, availablePlates: [45, 35, 25, 10, 5])
        XCTAssertTrue(result.plates.isEmpty)
        XCTAssertFalse(result.isExact)
    }

    func testDescription_SinglePlate() {
        let result = PlateCalculator.calculate(totalWeight: 135)
        // Should mention "45" in description
        XCTAssertTrue(result.description.contains("45"))
    }

    func testZeroWeight() {
        let result = PlateCalculator.calculate(totalWeight: 0)
        XCTAssertTrue(result.plates.isEmpty)
    }
}
