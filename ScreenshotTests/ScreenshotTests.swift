import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests"]
        app.launch()

        // Dismiss any system notifications/alerts
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let dismissButton = springboard.buttons["Dismiss"]
        if dismissButton.waitForExistence(timeout: 2) {
            dismissButton.tap()
        }
        sleep(1)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshots

    func testScreenshot01_WorkoutTemplates() throws {
        let workoutTab = app.tabBars.buttons["Workout"]
        if workoutTab.waitForExistence(timeout: 5) {
            workoutTab.tap()
        }
        sleep(2)
        takeScreenshot(named: "01_WorkoutTemplates")
    }

    func testScreenshot02_Dashboard() throws {
        let tab = app.tabBars.buttons["Program"]
        guard tab.waitForExistence(timeout: 5) else {
            XCTFail("Program tab not found")
            return
        }
        tab.tap()
        sleep(1)
        takeScreenshot(named: "02_Dashboard")
    }

    func testScreenshot03_History() throws {
        let tab = app.tabBars.buttons["History"]
        guard tab.waitForExistence(timeout: 5) else {
            XCTFail("History tab not found")
            return
        }
        tab.tap()
        sleep(1)
        takeScreenshot(named: "03_History")
    }

    func testScreenshot04_Settings() throws {
        let tab = app.tabBars.buttons["Settings"]
        guard tab.waitForExistence(timeout: 5) else {
            XCTFail("Settings tab not found")
            return
        }
        tab.tap()
        sleep(1)
        takeScreenshot(named: "04_Settings")
    }

    func testScreenshot05_ActiveWorkout() throws {
        let workoutTab = app.tabBars.buttons["Workout"]
        guard workoutTab.waitForExistence(timeout: 5) else {
            XCTFail("Workout tab not found")
            return
        }
        workoutTab.tap()
        sleep(1)

        let templateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Deadlift")).firstMatch
        if templateButton.waitForExistence(timeout: 3) {
            templateButton.tap()
        } else {
            let cells = app.cells
            if cells.count > 1 {
                cells.element(boundBy: 1).tap()
            } else {
                cells.firstMatch.tap()
            }
        }
        sleep(2)
        takeScreenshot(named: "05_ActiveWorkout")
    }

    func testScreenshot06_WorkoutDetail() throws {
        navigateToWorkoutDetail()
        takeScreenshot(named: "06_WorkoutDetail")
    }

    func testScreenshot07_ExerciseCharts() throws {
        navigateToExerciseDetail()

        let chartsTab = app.buttons["Charts"]
        if chartsTab.waitForExistence(timeout: 3) {
            chartsTab.tap()
        }
        sleep(1)
        takeScreenshot(named: "07_ExerciseCharts")
    }

    func testScreenshot08_ExerciseRecords() throws {
        navigateToExerciseDetail()

        let recordsTab = app.buttons["Records"]
        if recordsTab.waitForExistence(timeout: 3) {
            recordsTab.tap()
        }
        sleep(1)
        takeScreenshot(named: "08_ExerciseRecords")
    }

    func testScreenshot09_ExerciseHistory() throws {
        navigateToExerciseDetail()
        sleep(1)
        takeScreenshot(named: "09_ExerciseHistory")
    }

    // MARK: - Navigation Helpers

    private func navigateToWorkoutDetail() {
        let historyTab = app.tabBars.buttons["History"]
        guard historyTab.waitForExistence(timeout: 5) else { return }
        historyTab.tap()
        sleep(1)

        // History list uses NavigationLink wrapping each row
        // Look for a static text or button that contains workout info
        let workoutRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Deadlift + Bench")).firstMatch
        if workoutRow.waitForExistence(timeout: 3) {
            workoutRow.tap()
            sleep(2)
            return
        }

        // Fallback: tap first cell
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            firstCell.tap()
            sleep(2)
        }
    }

    private func navigateToExerciseDetail() {
        navigateToWorkoutDetail()

        // Look for exercise links by accessibility identifier
        let exerciseLink = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "exercise-link-"
        )).firstMatch

        if exerciseLink.waitForExistence(timeout: 3) {
            exerciseLink.tap()
            sleep(2)
            return
        }

        // Fallback: look for "Deadlift" text in the detail view
        let deadliftText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Deadlift")).firstMatch
        if deadliftText.waitForExistence(timeout: 3) {
            deadliftText.tap()
            sleep(2)
        }
    }

    // MARK: - Screenshot Helper

    private func takeScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
