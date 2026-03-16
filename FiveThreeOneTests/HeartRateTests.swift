import XCTest
@testable import FiveThreeOne

@MainActor
final class HeartRateTests: XCTestCase {

    // MARK: - RPE Estimation

    func testEstimateRPE_LowHR() {
        // 60 BPM at age 30 -> maxHR = 190, pctMax = 0.316
        // rpe = (0.316 - 0.35) / 0.065 = -0.52, clamped to 1
        let rpe = HeartRateManager.estimateRPE(heartRate: 60, age: 30)
        XCTAssertEqual(rpe, 1.0, accuracy: 0.01)
    }

    func testEstimateRPE_MediumHR() {
        // 140 BPM at age 30 -> maxHR = 190, pctMax = 0.737
        // rpe = (0.737 - 0.35) / 0.065 = 5.95
        let rpe = HeartRateManager.estimateRPE(heartRate: 140, age: 30)
        XCTAssertEqual(rpe, 5.95, accuracy: 0.1)
    }

    func testEstimateRPE_HighHR() {
        // 180 BPM at age 30 -> maxHR = 190, pctMax = 0.947
        // rpe = (0.947 - 0.35) / 0.065 = 9.19
        let rpe = HeartRateManager.estimateRPE(heartRate: 180, age: 30)
        XCTAssertEqual(rpe, 9.19, accuracy: 0.1)
    }

    func testEstimateRPE_MaxHR() {
        // 190 BPM at age 30 = 100% max HR
        // rpe = (1.0 - 0.35) / 0.065 = 10.0
        let rpe = HeartRateManager.estimateRPE(heartRate: 190, age: 30)
        XCTAssertEqual(rpe, 10.0)
    }

    func testEstimateRPE_AboveMax_ClampedTo10() {
        let rpe = HeartRateManager.estimateRPE(heartRate: 210, age: 30)
        XCTAssertEqual(rpe, 10.0)
    }

    func testEstimateRPE_DifferentAges() {
        // Same HR, different age -> different RPE
        let rpe20 = HeartRateManager.estimateRPE(heartRate: 160, age: 20)
        let rpe50 = HeartRateManager.estimateRPE(heartRate: 160, age: 50)
        // Older person has lower maxHR, so same absolute HR = higher RPE
        XCTAssertTrue(rpe50 > rpe20)
    }

    // MARK: - Calorie Estimation

    func testEstimateCalories_Male() {
        let cal = HeartRateManager.estimateCalories(
            averageHR: 140,
            durationMinutes: 60,
            bodyWeightKg: 80,
            age: 30,
            isMale: true
        )
        // Should be positive and reasonable (roughly 400-700 for an hour)
        XCTAssertGreaterThan(cal, 0)
        XCTAssertGreaterThan(cal, 200)
        XCTAssertLessThan(cal, 1000)
    }

    func testEstimateCalories_Female() {
        let cal = HeartRateManager.estimateCalories(
            averageHR: 140,
            durationMinutes: 60,
            bodyWeightKg: 65,
            age: 30,
            isMale: false
        )
        XCTAssertGreaterThan(cal, 0)
        XCTAssertGreaterThan(cal, 200)
        XCTAssertLessThan(cal, 1000)
    }

    func testEstimateCalories_MaleVsFemale_Different() {
        let male = HeartRateManager.estimateCalories(
            averageHR: 140, durationMinutes: 60, bodyWeightKg: 80, age: 30, isMale: true
        )
        let female = HeartRateManager.estimateCalories(
            averageHR: 140, durationMinutes: 60, bodyWeightKg: 80, age: 30, isMale: false
        )
        XCTAssertNotEqual(male, female)
    }

    func testEstimateCalories_ZeroDuration() {
        let cal = HeartRateManager.estimateCalories(
            averageHR: 140, durationMinutes: 0, bodyWeightKg: 80, age: 30, isMale: true
        )
        XCTAssertEqual(cal, 0.0, accuracy: 0.01)
    }

    func testEstimateCalories_ScalesWithDuration() {
        let cal30 = HeartRateManager.estimateCalories(
            averageHR: 140, durationMinutes: 30, bodyWeightKg: 80, age: 30, isMale: true
        )
        let cal60 = HeartRateManager.estimateCalories(
            averageHR: 140, durationMinutes: 60, bodyWeightKg: 80, age: 30, isMale: true
        )
        XCTAssertEqual(cal60, cal30 * 2, accuracy: 0.01)
    }
}
