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
        // Also dismiss inline notification banners by swiping up
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
            XCTFail("Program tab not found — app may be showing onboarding")
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
        // Navigate to Workout tab
        let workoutTab = app.tabBars.buttons["Workout"]
        guard workoutTab.waitForExistence(timeout: 5) else {
            XCTFail("Workout tab not found")
            return
        }
        workoutTab.tap()
        sleep(1)

        // Find the first template by looking for "Deadlift + Bench" or "Squat + OHP" text
        // The template cards are buttons in list cells
        let templateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Deadlift")).firstMatch
        if templateButton.waitForExistence(timeout: 3) {
            templateButton.tap()
        } else {
            // Fallback: tap second cell (skip the week picker section)
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
        // Navigate to History
        let historyTab = app.tabBars.buttons["History"]
        guard historyTab.waitForExistence(timeout: 5) else {
            XCTFail("History tab not found")
            return
        }
        historyTab.tap()
        sleep(1)

        // Tap into the first workout to see the detail view
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 3) else {
            takeScreenshot(named: "06_WorkoutDetail_Empty")
            return
        }

        // Tap the disclosure indicator / navigation link area
        firstCell.tap()
        sleep(2)
        takeScreenshot(named: "06_WorkoutDetail")
    }

    // MARK: - Helpers

    private func takeScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
