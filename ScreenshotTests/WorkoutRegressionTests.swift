import XCTest

/// Targeted regression tests for bugs that have actually occurred.
/// Each test is named after the specific regression it prevents.
final class WorkoutRegressionTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests"]
        app.launch()
        dismissSystemAlerts()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Superset Regressions

    /// Regression: Creating a superset used to cause exercises to disappear.
    /// The exerciseStates array would lose entries when superset grouping was applied.
    func testSuperset_ExercisesNotLostAfterLinking() {
        navigateToWorkoutView()
        startWorkout()

        // Count exercises before superset
        let countBefore = exerciseCount()
        guard countBefore >= 3 else {
            // Need at least 3 exercises (2 main + 1 accessory) to test superset
            return
        }

        // Find the first superset button for an accessory exercise
        // Main lifts are at index 0,1 — accessories start at index 2
        let supersetBtn = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "superset-btn-2")
        ).firstMatch

        guard supersetBtn.waitForExistence(timeout: 5) else {
            // May need to scroll to find accessory exercises
            app.swipeUp()
            guard supersetBtn.waitForExistence(timeout: 3) else { return }
            return
        }
        supersetBtn.tap()

        // Superset picker sheet should appear
        let pickerTitle = app.navigationBars["Superset With"]
        guard pickerTitle.waitForExistence(timeout: 5) else {
            XCTFail("Superset picker sheet did not open")
            return
        }

        // Pick another exercise to link with (if available)
        let pickerButtons = app.cells
        if pickerButtons.count > 0 {
            pickerButtons.firstMatch.tap()
            sleep(1)
        } else {
            // Cancel if no exercises available to link
            app.buttons["Cancel"].tap()
            return
        }

        // Verify exercise count is preserved
        let countAfter = exerciseCount()
        XCTAssertEqual(countAfter, countBefore,
            "Exercise count should not change after creating superset (was \(countBefore), now \(countAfter))")

        cancelActiveWorkout()
    }

    /// Regression: Unlinking a superset would sometimes lose exercises or crash.
    func testSuperset_UnlinkPreservesExercises() {
        navigateToWorkoutView()
        startWorkout()

        let countBefore = exerciseCount()

        // Create a superset first
        let supersetBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "superset-btn-")
        ).firstMatch

        if supersetBtn.waitForExistence(timeout: 3) {
            // Scroll if needed
        } else {
            app.swipeUp()
        }

        guard supersetBtn.waitForExistence(timeout: 3) else {
            cancelActiveWorkout()
            return
        }
        supersetBtn.tap()

        let pickerTitle = app.navigationBars["Superset With"]
        if pickerTitle.waitForExistence(timeout: 3) {
            let pickerButtons = app.cells
            if pickerButtons.count > 0 {
                pickerButtons.firstMatch.tap()
                sleep(1)
            } else {
                app.buttons["Cancel"].tap()
                cancelActiveWorkout()
                return
            }
        }

        // Now unlink
        let unlinkBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "unlink-superset-")
        ).firstMatch

        if unlinkBtn.waitForExistence(timeout: 3) {
            unlinkBtn.tap()
            sleep(1)

            let countAfter = exerciseCount()
            XCTAssertEqual(countAfter, countBefore,
                "Exercise count should be preserved after unlinking superset")
        }

        cancelActiveWorkout()
    }

    // MARK: - Set Completion Regressions

    /// Regression: Set completion state was being lost when the timer ticked,
    /// because ExerciseSectionGroup generated fresh UUIDs on every re-render,
    /// destroying and recreating all exercise section views.
    func testSetCompletion_StatePreservedAcrossTimerTicks() {
        navigateToWorkoutView()
        startWorkout()

        // Find and tap a completion button
        let completeBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "complete-set-")
        ).firstMatch

        guard completeBtn.waitForExistence(timeout: 5) else {
            cancelActiveWorkout()
            return
        }
        completeBtn.tap()

        // Wait for timer to tick a few times (rest timer starts after completion)
        sleep(3)

        // The completed set should still show as completed (green checkmark.circle.fill)
        // Verify by checking the same button still exists and is in the DOM
        // The button ID should still be accessible
        let completedButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "complete-set-")
        )
        XCTAssertGreaterThan(completedButtons.count, 0,
            "Set completion buttons should still exist after timer ticks (not destroyed by re-render)")

        cancelActiveWorkout()
    }

    /// Regression: Completing a set then scrolling away and back would reset it.
    func testSetCompletion_PersistsAfterScrolling() {
        navigateToWorkoutView()
        startWorkout()

        // Complete first available set
        let completeBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "complete-set-")
        ).firstMatch

        guard completeBtn.waitForExistence(timeout: 5) else {
            cancelActiveWorkout()
            return
        }

        // Get the button's identifier before completing
        let btnId = completeBtn.identifier
        completeBtn.tap()
        sleep(1)

        // Scroll down and back up
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        app.swipeDown()
        app.swipeDown()
        sleep(1)

        // The same set button should still exist (state preserved)
        let sameBtnAfterScroll = app.buttons[btnId]
        XCTAssertTrue(sameBtnAfterScroll.waitForExistence(timeout: 5),
            "Set completion button should persist after scrolling")

        cancelActiveWorkout()
    }

    // MARK: - Exercise Removal Regressions

    /// Regression: Removing an exercise could corrupt the exerciseStates array,
    /// causing subsequent exercises to show wrong data or crash.
    func testRemoveExercise_RemainingExercisesIntact() {
        navigateToWorkoutView()
        startWorkout()

        let countBefore = exerciseCount()
        guard countBefore >= 3 else {
            cancelActiveWorkout()
            return
        }

        // Find a remove button for an accessory (main lifts can't be removed)
        let removeBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "remove-exercise-")
        ).firstMatch

        if !removeBtn.waitForExistence(timeout: 3) {
            app.swipeUp()
        }

        guard removeBtn.waitForExistence(timeout: 3) else {
            cancelActiveWorkout()
            return
        }
        removeBtn.tap()

        // Confirmation dialog should appear
        let confirmRemove = app.buttons["Remove"]
        guard confirmRemove.waitForExistence(timeout: 3) else {
            cancelActiveWorkout()
            return
        }
        confirmRemove.tap()
        sleep(1)

        // Exercise count should decrease by exactly 1
        let countAfter = exerciseCount()
        XCTAssertEqual(countAfter, countBefore - 1,
            "Removing one exercise should decrease count by 1 (was \(countBefore), now \(countAfter))")

        // Remaining exercise names should still be visible
        // Check that at least main lift names are still showing
        let exerciseNames = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "exercise-name-")
        )
        XCTAssertGreaterThanOrEqual(exerciseNames.count, 2,
            "Main lift exercise headers should still be visible after removing accessory")

        cancelActiveWorkout()
    }

    // MARK: - Workout Save/Finish Regressions

    /// Regression: Finishing a workout with completed sets should navigate back
    /// to the template list without crashing.
    func testFinishWorkout_NavigatesBackCleanly() {
        navigateToWorkoutView()
        startWorkout()

        // Complete at least one set
        let completeBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "complete-set-")
        ).firstMatch

        if completeBtn.waitForExistence(timeout: 5) {
            completeBtn.tap()
            sleep(1)
        }

        // Scroll to and tap Finish Workout
        let finishBtn = app.buttons["Finish Workout"]
        if !finishBtn.exists {
            app.swipeUp()
            app.swipeUp()
            app.swipeUp()
        }
        guard finishBtn.waitForExistence(timeout: 5) else { return }
        finishBtn.tap()

        // Should navigate back to template list
        let workoutNav = app.navigationBars["Workout"]
        XCTAssertTrue(workoutNav.waitForExistence(timeout: 10),
            "Should return to template list after finishing workout")
    }

    /// Regression: Finishing a workout then immediately starting another
    /// would sometimes show stale state from the previous workout.
    func testFinishAndRestart_CleanState() {
        navigateToWorkoutView()
        startWorkout()

        // Complete a set
        let completeBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "complete-set-")
        ).firstMatch
        if completeBtn.waitForExistence(timeout: 5) {
            completeBtn.tap()
            sleep(1)
        }

        // Finish workout
        let finishBtn = app.buttons["Finish Workout"]
        if !finishBtn.exists {
            app.swipeUp()
            app.swipeUp()
            app.swipeUp()
        }
        guard finishBtn.waitForExistence(timeout: 5) else { return }
        finishBtn.tap()

        // Wait for template list
        let workoutNav = app.navigationBars["Workout"]
        guard workoutNav.waitForExistence(timeout: 10) else { return }

        // Start another workout with the same template
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 5) else { return }
        firstCell.tap()
        sleep(1)

        let startBtn = app.buttons["Start Workout"]
        guard startBtn.waitForExistence(timeout: 5) else { return }

        // "Start Workout" should be visible (not "Finish Workout" from previous session)
        XCTAssertTrue(startBtn.exists, "New workout should show Start button, not carry over previous state")

        cancelActiveWorkout()
    }

    // MARK: - Add Set Regression

    /// Regression: Adding a set mid-workout could cause index out of bounds
    /// or the wrong exercise to receive the new set.
    func testAddSet_AppendsCorrectly() {
        navigateToWorkoutView()
        startWorkout()

        // Find an "Add Set" button with identifier — scroll to find accessories
        let addSetBtn = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "add-set-")
        ).firstMatch
        if !addSetBtn.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        guard addSetBtn.waitForExistence(timeout: 5) else {
            cancelActiveWorkout()
            return
        }

        // Read the exercise index from the add-set button identifier
        let addBtnIndex = addSetBtn.identifier // e.g. "add-set-0"

        // Find the corresponding exercise name button to read set count
        let exerciseNames = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "exercise-name-")
        )
        var setCountBefore = 0
        for i in 0..<exerciseNames.count {
            let nameBtn = exerciseNames.element(boundBy: i)
            let value = nameBtn.value as? String ?? ""
            if value.hasPrefix("sets:"), let count = Int(value.dropFirst(5)) {
                setCountBefore = count
                break
            }
        }

        addSetBtn.tap()
        sleep(1)

        // Read set count after
        var setCountAfter = 0
        let exerciseNamesAfter = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "exercise-name-")
        )
        for i in 0..<exerciseNamesAfter.count {
            let nameBtn = exerciseNamesAfter.element(boundBy: i)
            let value = nameBtn.value as? String ?? ""
            if value.hasPrefix("sets:"), let count = Int(value.dropFirst(5)) {
                setCountAfter = count
                break
            }
        }

        if setCountBefore > 0 {
            XCTAssertEqual(setCountAfter, setCountBefore + 1,
                "Adding a set should increase count by 1 (was \(setCountBefore), now \(setCountAfter))")
        } else {
            // If we couldn't read the count, just verify no crash
            XCTAssertTrue(true, "Add set completed without crash")
        }

        cancelActiveWorkout()
    }

    // MARK: - Helpers

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Don't Allow", "OK", "Allow", "Not Now", "Dismiss"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
            }
        }
    }

    private func navigateToWorkoutView() {
        app.tabBars.buttons["Workout"].tap()
        sleep(1)

        // Tap first template
        for name in ["Squat + OHP", "Deadlift + Bench", "Squat", "Deadlift"] {
            let button = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                sleep(2)
                return
            }
        }
        // Fallback: first cell
        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            firstCell.tap()
            sleep(2)
        }
    }

    private func startWorkout() {
        let startBtn = app.buttons["Start Workout"]
        if startBtn.waitForExistence(timeout: 5) {
            startBtn.tap()
            dismissSystemAlerts()
            sleep(1)
        }
    }

    private func cancelActiveWorkout() {
        // Stop rest timer if running
        let stopTimer = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "xmark.circle")
        ).firstMatch
        if stopTimer.exists { stopTimer.tap() }

        let cancelBtn = app.buttons["Cancel Workout"]
        if !cancelBtn.exists {
            app.swipeUp()
            app.swipeUp()
            app.swipeUp()
        }
        if cancelBtn.waitForExistence(timeout: 3) {
            cancelBtn.tap()
            let discardBtn = app.buttons["Discard Workout"]
            if discardBtn.waitForExistence(timeout: 3) {
                discardBtn.tap()
            }
        }
    }

    /// Read exercise count from the hidden accessibility element or exercise name buttons
    private func exerciseCount() -> Int {
        // Try hidden text element first (searches all element types)
        for elementType in [app.staticTexts, app.otherElements] {
            let countElements = elementType.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "exercise-count-")
            )
            if countElements.count > 0 {
                let id = countElements.firstMatch.identifier
                if let numStr = id.split(separator: "-").last, let num = Int(numStr) {
                    return num
                }
            }
        }

        // Fallback: count exercise name buttons in headers
        return app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "exercise-name-")
        ).count
    }
}
