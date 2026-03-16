import XCTest
@testable import FiveThreeOne

final class ActiveWorkoutStoreTests: XCTestCase {

    override func tearDown() {
        ActiveWorkoutStore.delete()
    }

    func testSaveAndLoad_RoundTrip() {
        let snapshot = makeSnapshot()
        ActiveWorkoutStore.save(snapshot)

        let loaded = ActiveWorkoutStore.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.templateName, "Test Template")
        XCTAssertEqual(loaded?.cycleNumber, 1)
        XCTAssertEqual(loaded?.weekNumber, 2)
        XCTAssertEqual(loaded?.variant, "standard")
        XCTAssertEqual(loaded?.notes, "Test notes")
        XCTAssertEqual(loaded?.exercises.count, 1)
        XCTAssertEqual(loaded?.exercises[0].exerciseName, "Squat")
        XCTAssertEqual(loaded?.exercises[0].sets.count, 2)
        XCTAssertEqual(loaded?.exercises[0].sets[0].weight, 225)
        XCTAssertEqual(loaded?.exercises[0].sets[0].actualReps, 5)
        XCTAssertEqual(loaded?.exercises[0].sets[1].weight, 275)
        XCTAssertEqual(loaded?.exercises[0].sets[1].actualReps, 3)
    }

    func testHasRecoveryData_AfterSave() {
        XCTAssertFalse(ActiveWorkoutStore.hasRecoveryData)
        ActiveWorkoutStore.save(makeSnapshot())
        XCTAssertTrue(ActiveWorkoutStore.hasRecoveryData)
    }

    func testDelete_RemovesData() {
        ActiveWorkoutStore.save(makeSnapshot())
        XCTAssertTrue(ActiveWorkoutStore.hasRecoveryData)
        ActiveWorkoutStore.delete()
        XCTAssertFalse(ActiveWorkoutStore.hasRecoveryData)
    }

    func testLoad_WhenNoFile_ReturnsNil() {
        ActiveWorkoutStore.delete()
        XCTAssertNil(ActiveWorkoutStore.load())
    }

    func testLoad_MultipleExercises() {
        let snapshot = WorkoutSnapshot(
            templateName: "Full Workout",
            cycleNumber: 2,
            weekNumber: 3,
            variant: "boringButBig",
            workoutStartTime: Date.now.addingTimeInterval(-3600),
            notes: "",
            exercises: [
                WorkoutSnapshot.ExerciseSnapshot(
                    id: UUID().uuidString,
                    exerciseName: "Bench Press",
                    mainLift: "bench",
                    sets: [CompletedSet(weight: 185, targetReps: 5, actualReps: 5, setType: .main)],
                    supersetGroup: nil,
                    isUnilateral: false,
                    equipmentType: "barbell",
                    isTimed: false,
                    supersetSubGroup: nil
                ),
                WorkoutSnapshot.ExerciseSnapshot(
                    id: UUID().uuidString,
                    exerciseName: "Dumbbell Row",
                    mainLift: nil,
                    sets: [CompletedSet(weight: 60, targetReps: 10, actualReps: 10, setType: .accessory)],
                    supersetGroup: 1,
                    isUnilateral: true,
                    equipmentType: "dumbbell",
                    isTimed: false,
                    supersetSubGroup: 0
                ),
            ],
            savedAt: .now
        )
        ActiveWorkoutStore.save(snapshot)

        let loaded = ActiveWorkoutStore.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.exercises.count, 2)
        XCTAssertEqual(loaded?.exercises[1].exerciseName, "Dumbbell Row")
        XCTAssertTrue(loaded?.exercises[1].isUnilateral ?? false)
        XCTAssertEqual(loaded?.exercises[1].supersetGroup, 1)
    }

    // MARK: - Helpers

    private func makeSnapshot() -> WorkoutSnapshot {
        WorkoutSnapshot(
            templateName: "Test Template",
            cycleNumber: 1,
            weekNumber: 2,
            variant: "standard",
            workoutStartTime: Date.now.addingTimeInterval(-1800),
            notes: "Test notes",
            exercises: [
                WorkoutSnapshot.ExerciseSnapshot(
                    id: UUID().uuidString,
                    exerciseName: "Squat",
                    mainLift: "squat",
                    sets: [
                        CompletedSet(weight: 225, targetReps: 5, actualReps: 5, setType: .main),
                        CompletedSet(weight: 275, targetReps: 3, actualReps: 3, setType: .main),
                    ],
                    supersetGroup: nil,
                    isUnilateral: false,
                    equipmentType: "barbell",
                    isTimed: false,
                    supersetSubGroup: nil
                )
            ],
            savedAt: .now
        )
    }
}
