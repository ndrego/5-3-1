import XCTest
@testable import FiveThreeOne

final class CompletedSetTests: XCTestCase {

    func testIsComplete_WhenActualRepsPositive() {
        let set = CompletedSet(weight: 135, targetReps: 5, actualReps: 5)
        XCTAssertTrue(set.isComplete)
    }

    func testIsComplete_WhenActualRepsZero() {
        let set = CompletedSet(weight: 135, targetReps: 5, actualReps: 0)
        XCTAssertFalse(set.isComplete)
    }

    func testExceededTarget_AMRAP_Exceeded() {
        let set = CompletedSet(weight: 135, targetReps: 5, actualReps: 8, isAMRAP: true)
        XCTAssertTrue(set.exceededTarget)
    }

    func testExceededTarget_AMRAP_NotExceeded() {
        let set = CompletedSet(weight: 135, targetReps: 5, actualReps: 5, isAMRAP: true)
        XCTAssertFalse(set.exceededTarget)
    }

    func testExceededTarget_NotAMRAP() {
        let set = CompletedSet(weight: 135, targetReps: 5, actualReps: 8, isAMRAP: false)
        XCTAssertFalse(set.exceededTarget)
    }

    func testCodableRoundTrip() throws {
        let original = CompletedSet(
            weight: 225,
            targetReps: 3,
            actualReps: 5,
            isAMRAP: true,
            setType: .main,
            averageHR: 155.5,
            restSeconds: 180
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompletedSet.self, from: data)
        XCTAssertEqual(decoded.weight, original.weight)
        XCTAssertEqual(decoded.targetReps, original.targetReps)
        XCTAssertEqual(decoded.actualReps, original.actualReps)
        XCTAssertEqual(decoded.isAMRAP, original.isAMRAP)
        XCTAssertEqual(decoded.setType, original.setType)
        XCTAssertEqual(decoded.averageHR, original.averageHR)
        XCTAssertEqual(decoded.restSeconds, original.restSeconds)
    }
}

final class ExercisePerformanceTests: XCTestCase {

    func testIsMainLift() {
        let main = ExercisePerformance(exerciseName: "Squat", mainLift: "squat")
        XCTAssertTrue(main.isMainLift)
        XCTAssertEqual(main.lift, .squat)

        let accessory = ExercisePerformance(exerciseName: "Dumbbell Row")
        XCTAssertFalse(accessory.isMainLift)
        XCTAssertNil(accessory.lift)
    }

    func testTotalVolume_Normal() {
        let perf = ExercisePerformance(
            exerciseName: "Bench Press",
            sets: [
                CompletedSet(weight: 135, targetReps: 5, actualReps: 5, setType: .main),
                CompletedSet(weight: 155, targetReps: 5, actualReps: 5, setType: .main),
                CompletedSet(weight: 175, targetReps: 5, actualReps: 3, setType: .main),
            ]
        )
        // 135*5 + 155*5 + 175*3 = 675 + 775 + 525 = 1975
        XCTAssertEqual(perf.totalVolume, 1975)
    }

    func testTotalVolume_ExcludesWarmup() {
        let perf = ExercisePerformance(
            exerciseName: "Squat",
            sets: [
                CompletedSet(weight: 95, targetReps: 5, actualReps: 5, setType: .warmup),
                CompletedSet(weight: 135, targetReps: 5, actualReps: 5, setType: .main),
            ]
        )
        // Only main: 135*5 = 675
        XCTAssertEqual(perf.totalVolume, 675)
    }

    func testTotalVolume_Unilateral_Doubled() {
        let perf = ExercisePerformance(
            exerciseName: "Bulgarian Split Squat",
            sets: [
                CompletedSet(weight: 50, targetReps: 10, actualReps: 10, setType: .accessory),
            ],
            isUnilateral: true
        )
        // 50*10 = 500, doubled = 1000
        XCTAssertEqual(perf.totalVolume, 1000)
    }

    func testTotalVolume_ExcludesIncomplete() {
        let perf = ExercisePerformance(
            exerciseName: "OHP",
            sets: [
                CompletedSet(weight: 95, targetReps: 5, actualReps: 5, setType: .main),
                CompletedSet(weight: 105, targetReps: 5, actualReps: 0, setType: .main),
            ]
        )
        // Only first set complete: 95*5 = 475
        XCTAssertEqual(perf.totalVolume, 475)
    }

    func testCompletedWorkingSets() {
        let perf = ExercisePerformance(
            exerciseName: "Deadlift",
            sets: [
                CompletedSet(weight: 135, targetReps: 5, actualReps: 5, setType: .warmup),
                CompletedSet(weight: 225, targetReps: 5, actualReps: 5, setType: .main),
                CompletedSet(weight: 275, targetReps: 3, actualReps: 3, setType: .main),
                CompletedSet(weight: 315, targetReps: 1, actualReps: 0, setType: .main),
            ]
        )
        // 2 completed non-warmup sets
        XCTAssertEqual(perf.completedWorkingSets, 2)
    }

    func testTotalReps() {
        let perf = ExercisePerformance(
            exerciseName: "Bench",
            sets: [
                CompletedSet(weight: 95, targetReps: 5, actualReps: 5, setType: .warmup),
                CompletedSet(weight: 135, targetReps: 5, actualReps: 5, setType: .main),
                CompletedSet(weight: 155, targetReps: 3, actualReps: 3, setType: .main),
            ]
        )
        // Excludes warmup: 5 + 3 = 8
        XCTAssertEqual(perf.totalReps, 8)
    }

    func testBestSet() {
        let perf = ExercisePerformance(
            exerciseName: "Squat",
            sets: [
                CompletedSet(weight: 225, targetReps: 5, actualReps: 5, setType: .main),
                CompletedSet(weight: 275, targetReps: 3, actualReps: 3, setType: .main),
                CompletedSet(weight: 275, targetReps: 1, actualReps: 5, setType: .main),
            ]
        )
        let best = perf.bestSet
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.weight, 275)
        XCTAssertEqual(best?.actualReps, 5) // Higher reps wins tiebreaker
    }
}

final class LiftTests: XCTestCase {

    func testProgressionIncrements() {
        XCTAssertEqual(Lift.squat.progressionIncrement, 10.0)
        XCTAssertEqual(Lift.deadlift.progressionIncrement, 10.0)
        XCTAssertEqual(Lift.bench.progressionIncrement, 5.0)
        XCTAssertEqual(Lift.overheadPress.progressionIncrement, 5.0)
    }

    func testIsUpperBody() {
        XCTAssertFalse(Lift.squat.isUpperBody)
        XCTAssertFalse(Lift.deadlift.isUpperBody)
        XCTAssertTrue(Lift.bench.isUpperBody)
        XCTAssertTrue(Lift.overheadPress.isUpperBody)
    }

    func testFromStrongName() {
        XCTAssertEqual(Lift.fromStrongName("Bench Press (Barbell)"), .bench)
        XCTAssertEqual(Lift.fromStrongName("Squat (Barbell)"), .squat)
        XCTAssertEqual(Lift.fromStrongName("Deadlift (Barbell)"), .deadlift)
        XCTAssertNil(Lift.fromStrongName("Unknown Exercise"))
    }

    func testDisplayNames() {
        XCTAssertEqual(Lift.squat.displayName, "Squat")
        XCTAssertEqual(Lift.bench.displayName, "Bench Press")
        XCTAssertEqual(Lift.deadlift.displayName, "Deadlift")
        XCTAssertEqual(Lift.overheadPress.displayName, "Overhead Press")
    }

    func testShortNames() {
        XCTAssertEqual(Lift.squat.shortName, "SQ")
        XCTAssertEqual(Lift.bench.shortName, "BP")
        XCTAssertEqual(Lift.deadlift.shortName, "DL")
        XCTAssertEqual(Lift.overheadPress.shortName, "OHP")
    }
}

final class ProgramVariantTests: XCTestCase {

    func testHasAMRAP() {
        XCTAssertTrue(ProgramVariant.standard.hasAMRAP)
        XCTAssertTrue(ProgramVariant.boringButBig.hasAMRAP)
        XCTAssertTrue(ProgramVariant.firstSetLast.hasAMRAP)
        XCTAssertFalse(ProgramVariant.fivesPro.hasAMRAP)
        XCTAssertFalse(ProgramVariant.bbbBeefcake.hasAMRAP)
        XCTAssertTrue(ProgramVariant.ssl.hasAMRAP)
    }

    func testSupplementalSets() {
        XCTAssertEqual(ProgramVariant.standard.supplementalSets, 0)
        XCTAssertEqual(ProgramVariant.fivesPro.supplementalSets, 0)
        XCTAssertEqual(ProgramVariant.boringButBig.supplementalSets, 5)
        XCTAssertEqual(ProgramVariant.bbbBeefcake.supplementalSets, 5)
        XCTAssertEqual(ProgramVariant.firstSetLast.supplementalSets, 5)
        XCTAssertEqual(ProgramVariant.ssl.supplementalSets, 5)
    }

    func testSupplementalReps() {
        XCTAssertEqual(ProgramVariant.boringButBig.supplementalReps, 10)
        XCTAssertEqual(ProgramVariant.bbbBeefcake.supplementalReps, 10)
        XCTAssertEqual(ProgramVariant.firstSetLast.supplementalReps, 5)
        XCTAssertEqual(ProgramVariant.ssl.supplementalReps, 5)
    }
}
