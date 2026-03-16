import XCTest
@testable import FiveThreeOne

@MainActor
final class RestTimerStateTests: XCTestCase {

    func testStart_SetsState() {
        let timer = RestTimerState()
        timer.start(seconds: 180)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.totalSeconds, 180)
        XCTAssertEqual(timer.remainingSeconds, 180)
        XCTAssertFalse(timer.recovered)
        timer.stop()
    }

    func testStop_ClearsState() {
        let timer = RestTimerState()
        timer.start(seconds: 120)
        timer.stop()
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertFalse(timer.recovered)
        XCTAssertNil(timer.recoveryTargetHR)
    }

    func testAdjustTime_Positive() {
        let timer = RestTimerState()
        timer.start(seconds: 60)
        timer.adjustTime(by: 30)
        XCTAssertEqual(timer.totalSeconds, 90)
        XCTAssertEqual(timer.remainingSeconds, 90)
        timer.stop()
    }

    func testAdjustTime_Negative_ClampsToZero() {
        let timer = RestTimerState()
        timer.start(seconds: 60)
        timer.adjustTime(by: -200)
        XCTAssertEqual(timer.totalSeconds, 0)
        XCTAssertEqual(timer.remainingSeconds, 0)
        timer.stop()
    }

    func testProgress_AtStart() {
        let timer = RestTimerState()
        timer.start(seconds: 100)
        // remainingSeconds = totalSeconds at start, so progress = 0
        XCTAssertEqual(timer.progress, 0.0, accuracy: 0.001)
        timer.stop()
    }

    func testProgress_DefaultState() {
        let timer = RestTimerState()
        // Default: totalSeconds=180, remainingSeconds=0 → progress=1.0 (fully elapsed)
        XCTAssertEqual(timer.progress, 1.0, accuracy: 0.001)
    }

    func testFormattedRemaining() {
        let timer = RestTimerState()
        timer.start(seconds: 90)
        XCTAssertEqual(timer.formattedRemaining, "1:30")
        timer.stop()

        timer.start(seconds: 5)
        XCTAssertEqual(timer.formattedRemaining, "0:05")
        timer.stop()

        timer.start(seconds: 300)
        XCTAssertEqual(timer.formattedRemaining, "5:00")
        timer.stop()
    }

    func testCheckRecovery_BelowTarget() {
        let timer = RestTimerState()
        timer.start(seconds: 180, recoveryHR: 120)
        timer.checkRecovery(currentHR: 115)
        XCTAssertTrue(timer.recovered)
        timer.stop()
    }

    func testCheckRecovery_AboveTarget() {
        let timer = RestTimerState()
        timer.start(seconds: 180, recoveryHR: 120)
        timer.checkRecovery(currentHR: 140)
        XCTAssertFalse(timer.recovered)
        timer.stop()
    }

    func testCheckRecovery_NoTarget() {
        let timer = RestTimerState()
        timer.start(seconds: 180)
        timer.checkRecovery(currentHR: 100)
        XCTAssertFalse(timer.recovered)
        timer.stop()
    }

    func testCheckRecovery_AlreadyRecovered_NoChange() {
        let timer = RestTimerState()
        timer.start(seconds: 180, recoveryHR: 120)
        timer.checkRecovery(currentHR: 110)
        XCTAssertTrue(timer.recovered)
        // Calling again with high HR shouldn't change state
        timer.checkRecovery(currentHR: 150)
        XCTAssertTrue(timer.recovered)
        timer.stop()
    }

    func testStart_WithRecoveryHR() {
        let timer = RestTimerState()
        timer.start(seconds: 120, recoveryHR: 110)
        XCTAssertEqual(timer.recoveryTargetHR, 110)
        timer.stop()
    }
}
