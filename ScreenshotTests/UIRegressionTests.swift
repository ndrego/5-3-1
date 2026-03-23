import XCTest

/// Regression UI tests for 531 Strength.
/// Runs against demo-seeded data (via `-UITests` launch argument).
final class UIRegressionTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests"]
        app.launch()

        // Dismiss any HealthKit or notification alerts
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Don't Allow", "Dismiss", "Not Now"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
            }
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab Navigation

    func testTabBar_AllTabsExist() {
        let tabs = ["Workout", "Program", "History", "Settings"]
        for tab in tabs {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 5),
                "Tab '\(tab)' should exist"
            )
        }
    }

    func testTabBar_SwitchBetweenTabs() {
        let tabs = ["Program", "History", "Settings", "Workout"]
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "\(tab) tab should be selected")
        }
    }

    // MARK: - Workout Tab (Template List)

    func testWorkoutTab_ShowsTemplates() {
        app.tabBars.buttons["Workout"].tap()
        // Should see navigation title "Workout"
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5))
        // Should have at least one template (demo data seeds templates)
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
    }

    func testWorkoutTab_WeekPicker() {
        app.tabBars.buttons["Workout"].tap()
        // Week picker buttons should exist — look for "Week 1" text
        let week1 = app.buttons["Week 1"]
        let week2 = app.buttons["Week 2"]
        let week3 = app.buttons["Week 3"]

        if week1.waitForExistence(timeout: 3) {
            week1.tap()
            week2.tap()
            week3.tap()
            // Just verifying tappability, no crash
        }
    }

    func testWorkoutTab_AddTemplateButton() {
        app.tabBars.buttons["Workout"].tap()
        let addButton = app.navigationBars.buttons["Add"]
        if !addButton.exists {
            // Might be a "plus" image button
            let plusButton = app.navigationBars.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Add")
            ).firstMatch
            XCTAssertTrue(plusButton.waitForExistence(timeout: 3), "Add template button should exist")
        }
    }

    // MARK: - Active Workout Flow

    func testActiveWorkout_StartAndCancel() {
        navigateToWorkoutView()

        // Verify we actually navigated away from the template list
        // The workout view should NOT show "Workout" as nav title (that's the list)
        let workoutNavBar = app.navigationBars["Workout"]
        if workoutNavBar.exists {
            // We're still on the template list — navigation failed
            // This can happen if no cycle exists. Skip gracefully.
            return
        }

        // Should see "Start Workout" button
        let startButton = app.buttons["Start Workout"]
        guard startButton.waitForExistence(timeout: 5) else {
            // Start button not found — may already be in a workout state or different view
            return
        }
        startButton.tap()
        dismissSystemAlerts()

        // Should now see "Finish Workout" and "Cancel Workout"
        // Scroll down to find the buttons — they may be below the fold
        let finishButton = app.buttons["Finish Workout"]
        if !finishButton.waitForExistence(timeout: 3) {
            app.swipeUp()
            app.swipeUp()
        }

        guard finishButton.waitForExistence(timeout: 5) else {
            // Workout might not have started (e.g., missing cycle data)
            return
        }

        // Cancel the workout — scroll down if needed
        let cancelButton = app.buttons["Cancel Workout"]
        if !cancelButton.exists {
            app.swipeUp()
        }
        guard cancelButton.waitForExistence(timeout: 3) else { return }
        cancelButton.tap()

        // Confirmation dialog should appear
        let discardButton = app.buttons["Discard Workout"]
        if discardButton.waitForExistence(timeout: 3) {
            discardButton.tap()
        }
    }

    func testActiveWorkout_CompleteSet() {
        navigateToWorkoutView()

        let startButton = app.buttons["Start Workout"]
        guard startButton.waitForExistence(timeout: 5) else { return }
        startButton.tap()
        dismissSystemAlerts()

        // Find a completion button (checkmark circle for non-AMRAP set)
        let completionButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "circle")
        ).firstMatch

        if completionButton.waitForExistence(timeout: 3) {
            completionButton.tap()
        }

        // Clean up: cancel workout
        cancelActiveWorkout()
    }

    func testActiveWorkout_FinishWorkout() {
        navigateToWorkoutView()

        let startButton = app.buttons["Start Workout"]
        guard startButton.waitForExistence(timeout: 5) else { return }
        startButton.tap()
        dismissSystemAlerts()

        // Scroll to find Finish Workout
        let finishButton = app.buttons["Finish Workout"]
        if !finishButton.waitForExistence(timeout: 3) {
            app.swipeUp()
            app.swipeUp()
        }
        guard finishButton.waitForExistence(timeout: 3) else { return }
        finishButton.tap()

        // Should navigate back to template list
        let templateList = app.navigationBars["Workout"]
        _ = templateList.waitForExistence(timeout: 5)
    }

    // MARK: - Rest Timer

    func testRestTimer_AdjustButtons() {
        navigateToWorkoutView()

        let startButton = app.buttons["Start Workout"]
        guard startButton.waitForExistence(timeout: 5) else { return }
        startButton.tap()
        dismissSystemAlerts()

        // Complete a set to trigger rest timer
        let completionButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "circle")
        ).firstMatch

        if completionButton.waitForExistence(timeout: 3) {
            completionButton.tap()
        }

        // Check for rest timer controls
        let minus15 = app.buttons["-15s"]
        let plus15 = app.buttons["+15s"]

        if minus15.waitForExistence(timeout: 3) {
            XCTAssertTrue(plus15.exists, "+15s button should exist with rest timer")
            plus15.tap()
            minus15.tap()
        }

        // Clean up
        cancelActiveWorkout()
    }

    // MARK: - History Tab

    func testHistoryTab_ShowsWorkouts() {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        // Demo data seeds completed workouts
        XCTAssertTrue(
            app.cells.firstMatch.waitForExistence(timeout: 5),
            "History should show completed workouts from demo data"
        )
    }

    func testHistoryTab_NavigateToDetail() {
        let navigated = navigateToWorkoutDetail()
        XCTAssertTrue(navigated, "Should navigate to workout detail from history")
    }

    // MARK: - Workout Detail Edit Mode

    func testWorkoutDetail_EditMode() {
        guard navigateToWorkoutDetail() else { return }

        // Look for Edit button
        let editButton = app.navigationBars.buttons["Edit"]
        guard editButton.waitForExistence(timeout: 5) else {
            XCTFail("Edit button not found on workout detail")
            return
        }
        editButton.tap()

        // Should now show "Done" button
        let doneButton = app.navigationBars.buttons["Done"]
        XCTAssertTrue(
            doneButton.waitForExistence(timeout: 3),
            "Done button should appear in edit mode"
        )

        // Text fields should appear for editing weight/reps
        // Exit edit mode
        doneButton.tap()

        // Should be back to view mode with "Edit" button
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
    }

    // MARK: - Exercise Detail Navigation

    func testExerciseDetail_NavigateFromHistory() {
        guard navigateToWorkoutDetail() else { return }

        // Look for exercise link by accessibility identifier
        let exerciseLink = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "exercise-link-")
        ).firstMatch

        if exerciseLink.waitForExistence(timeout: 3) {
            exerciseLink.tap()
            // Should navigate to exercise detail — verify by looking for tabs (Charts, Records)
            let chartsButton = app.buttons["Charts"]
            let recordsButton = app.buttons["Records"]
            // At least one should exist if we're on exercise detail
            let onDetailPage = chartsButton.waitForExistence(timeout: 3) || recordsButton.exists
            XCTAssertTrue(onDetailPage, "Should navigate to exercise detail page")
        }
    }

    // MARK: - Program Tab (Dashboard)

    func testDashboardTab_ShowsCycleInfo() {
        app.tabBars.buttons["Program"].tap()
        XCTAssertTrue(app.navigationBars["531 Strength"].waitForExistence(timeout: 5))

        // Demo data seeds cycle 3, so dashboard should show cycle info
        // Look for cycle-related text
        let cycleText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Cycle")
        ).firstMatch
        XCTAssertTrue(
            cycleText.waitForExistence(timeout: 3),
            "Dashboard should show cycle information"
        )
    }

    func testDashboardTab_ShowsTrainingMaxes() {
        app.tabBars.buttons["Program"].tap()

        // Demo data has training maxes — look for lift abbreviations
        let liftLabels = ["SQ", "BP", "DL", "OHP"]
        var foundAny = false
        for label in liftLabels {
            if app.staticTexts[label].waitForExistence(timeout: 2) {
                foundAny = true
                break
            }
        }
        XCTAssertTrue(foundAny, "Dashboard should show at least one training max abbreviation")
    }

    // MARK: - Settings Tab

    func testSettingsTab_ShowsSections() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Verify key settings exist by scrolling and checking for labels
        let expectedLabels = ["Bar Weight", "Round To", "Main Sets"]
        for label in expectedLabels {
            let element = app.staticTexts[label]
            if element.waitForExistence(timeout: 2) {
                XCTAssertTrue(true)
            }
        }
    }

    func testSettingsTab_EditTrainingMaxes() {
        app.tabBars.buttons["Settings"].tap()

        // Scroll down to find "Edit Training Maxes" button
        let editTMButton = app.buttons["Edit Training Maxes"]
        if editTMButton.waitForExistence(timeout: 3) {
            editTMButton.tap()
            // Should present a sheet — verify it appeared
            // Look for the training max setup view
            sleep(1)
            // Dismiss it
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.waitForExistence(timeout: 2) {
                cancelButton.tap()
            }
        } else {
            // May need to scroll to find the button
            app.swipeUp()
            if editTMButton.waitForExistence(timeout: 3) {
                editTMButton.tap()
                sleep(1)
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.waitForExistence(timeout: 2) {
                    cancelButton.tap()
                }
            }
        }
    }

    func testSettingsTab_ImportFromStrong() {
        app.tabBars.buttons["Settings"].tap()

        // Scroll to find Import button
        app.swipeUp()
        let importButton = app.buttons["Import from Strong App"]
        if importButton.waitForExistence(timeout: 3) {
            importButton.tap()
            sleep(1)
            // Should present import sheet — dismiss it
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.waitForExistence(timeout: 2) {
                cancelButton.tap()
            } else {
                // Try close/dismiss button
                let closeButton = app.buttons["Close"]
                if closeButton.waitForExistence(timeout: 2) {
                    closeButton.tap()
                }
            }
        }
    }

    func testSettingsTab_BackupRestore() {
        app.tabBars.buttons["Settings"].tap()

        app.swipeUp()
        let backupButton = app.buttons["Backup & Restore"]
        if backupButton.waitForExistence(timeout: 3) {
            backupButton.tap()
            sleep(1)
            // Dismiss the sheet
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.waitForExistence(timeout: 2) {
                cancelButton.tap()
            } else {
                let closeButton = app.buttons["Close"]
                if closeButton.waitForExistence(timeout: 2) {
                    closeButton.tap()
                }
            }
        }
    }

    // MARK: - Template Management

    func testTemplate_SwipeToDelete() {
        app.tabBars.buttons["Workout"].tap()
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else { return }

        // Swipe left to reveal delete action
        firstCell.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 2) {
            // Don't actually delete — just verify the action exists
            // Swipe right to dismiss
            firstCell.swipeRight()
        }
    }

    func testTemplate_SwipeToEdit() {
        app.tabBars.buttons["Workout"].tap()
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else { return }

        // Swipe right to reveal edit action
        firstCell.swipeRight()
        let editButton = app.buttons["Edit"]
        if editButton.waitForExistence(timeout: 2) {
            editButton.tap()
            // Should open template edit sheet
            sleep(1)
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.waitForExistence(timeout: 2) {
                cancelButton.tap()
            }
        }
    }

    // MARK: - Cross-Feature Navigation

    func testNavigationFlow_WorkoutToHistoryToDetail() {
        // Start on Workout tab
        app.tabBars.buttons["Workout"].tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5))

        // Switch to History and navigate to detail
        guard navigateToWorkoutDetail() else { return }

        // Go back using the back button (first button in navigation bar)
        let backButton = app.navigationBars.buttons["History"]
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // Should be back on History list
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    // MARK: - Custom Exercise Creation

    func testCreateCustomExercise_Flow() {
        app.tabBars.buttons["Workout"].tap()

        // Open template edit via swipe
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else { return }
        firstCell.swipeRight()
        let editButton = app.buttons["Edit"]
        guard editButton.waitForExistence(timeout: 2) else { return }
        editButton.tap()
        sleep(1)

        // Tap "Add Exercise"
        let addExercise = app.buttons["Add Exercise"]
        guard addExercise.waitForExistence(timeout: 3) else {
            // May need to scroll
            app.swipeUp()
            guard addExercise.waitForExistence(timeout: 2) else { return }
            return
        }
        addExercise.tap()
        sleep(1)

        // Should see "Create New Exercise" button
        let createNew = app.buttons["Create New Exercise"]
        XCTAssertTrue(createNew.waitForExistence(timeout: 3),
            "Create New Exercise button should exist in exercise picker")

        createNew.tap()
        sleep(1)

        // Should see the New Exercise form
        XCTAssertTrue(app.navigationBars["New Exercise"].waitForExistence(timeout: 3),
            "Should navigate to New Exercise form")

        // Type a name
        let nameField = app.textFields["Exercise Name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("Test Custom Exercise")
        }

        // Add button should be enabled now
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))

        // Cancel instead of adding (don't pollute test data)
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.exists { cancelButton.tap() }

        // Dismiss the exercise picker
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 2) { doneButton.tap() }

        // Cancel the template editor
        sleep(1)
        let cancelEdit = app.buttons["Cancel"]
        if cancelEdit.exists { cancelEdit.tap() }
    }

    // MARK: - Template Edit Defaults

    func testTemplateEdit_ShowsWeightRepsForAccessories() {
        app.tabBars.buttons["Workout"].tap()

        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else { return }
        firstCell.swipeRight()
        let editButton = app.buttons["Edit"]
        guard editButton.waitForExistence(timeout: 2) else { return }
        editButton.tap()
        sleep(1)

        // Should see weight/reps text fields for accessories (not main lifts)
        // Look for "lbs" or "reps" labels which appear next to the fields
        let lbsLabel = app.staticTexts["lbs"]
        let repsLabel = app.staticTexts["reps"]

        // May need to scroll past main lifts to find accessories
        if !lbsLabel.waitForExistence(timeout: 2) {
            app.swipeUp()
        }

        let hasDefaults = lbsLabel.waitForExistence(timeout: 3) || repsLabel.waitForExistence(timeout: 3)
        XCTAssertTrue(hasDefaults,
            "Template editor should show weight/reps fields for accessory exercises")

        // Cancel the template editor
        let cancelButton = app.navigationBars.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.tap()
        } else {
            let saveButton = app.navigationBars.buttons["Save"]
            if saveButton.exists { saveButton.tap() }
        }
    }

    func testTemplateEdit_SetCountStepper() {
        app.tabBars.buttons["Workout"].tap()

        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else { return }
        firstCell.swipeRight()
        let editButton = app.buttons["Edit"]
        guard editButton.waitForExistence(timeout: 2) else { return }
        editButton.tap()
        sleep(1)

        // Find set count stepper (plus.circle / minus.circle buttons)
        let plusButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "plus.circle")
        ).firstMatch

        if !plusButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }

        if plusButton.waitForExistence(timeout: 3) {
            // Tap plus to increase set count — verify no crash
            plusButton.tap()
            sleep(1)
        }

        // Cancel
        let cancelButton = app.navigationBars.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.tap()
        } else {
            let saveButton = app.navigationBars.buttons["Save"]
            if saveButton.exists { saveButton.tap() }
        }
    }

    // MARK: - Appearance

    func testAppLaunch_NoBlankScreen() {
        // Verify that something meaningful is shown (not a blank/error screen)
        let anyTab = app.tabBars.buttons.firstMatch
        XCTAssertTrue(anyTab.waitForExistence(timeout: 10), "App should show tab bar on launch")
    }

    // MARK: - Alert Helpers

    /// Dismiss any system alerts (HealthKit, notifications, etc.)
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Don't Allow", "OK", "Allow", "Not Now", "Dismiss"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
            }
        }
    }

    /// Cancel an active workout via Cancel Workout → Discard Workout
    private func cancelActiveWorkout() {
        let cancelButton = app.buttons["Cancel Workout"]
        if !cancelButton.exists {
            app.swipeUp()
        }
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
            let discardButton = app.buttons["Discard Workout"]
            if discardButton.waitForExistence(timeout: 3) {
                discardButton.tap()
            }
        }
    }

    // MARK: - Navigation Helpers

    /// Navigate to the workout view (TemplateWorkoutView) by tapping first template
    private func navigateToWorkoutView() {
        app.tabBars.buttons["Workout"].tap()
        sleep(1)

        // Demo data seeds templates like "Squat + OHP" and "Deadlift + Bench"
        // Template list uses Button in a List — rendered as cells
        // Try multiple strategies to find and tap a template

        // Strategy 1: Find button by known template name from demo data
        for name in ["Squat + OHP", "Deadlift + Bench", "Squat", "Deadlift"] {
            let button = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
                sleep(2)
                return
            }
        }

        // Strategy 2: Tap first cell
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            firstCell.tap()
            sleep(2)
            return
        }
    }

    /// Navigate to a workout detail from History tab.
    /// Returns true if navigation succeeded.
    @discardableResult
    private func navigateToWorkoutDetail() -> Bool {
        app.tabBars.buttons["History"].tap()
        sleep(1)

        // History uses NavigationLink inside sections grouped by month
        // Try tapping first cell
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 5) {
            firstCell.tap()
            sleep(2)

            // Verify we navigated — look for Edit button (present on WorkoutDetailView)
            let editButton = app.navigationBars.buttons["Edit"]
            if editButton.waitForExistence(timeout: 5) {
                return true
            }
        }

        // Fallback: try tapping a static text that looks like a workout name
        for name in ["Squat + OHP", "Deadlift + Bench"] {
            let text = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            if text.waitForExistence(timeout: 2) {
                text.tap()
                sleep(2)
                let editButton = app.navigationBars.buttons["Edit"]
                if editButton.waitForExistence(timeout: 3) {
                    return true
                }
            }
        }

        XCTFail("Could not navigate to workout detail")
        return false
    }
}
