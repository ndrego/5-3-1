import Foundation
import SwiftData

/// Seeds realistic demo data for App Store screenshots and UI tests.
/// Activated by the `-UITests` launch argument.
enum DemoDataSeeder {

    static func seed(in context: ModelContext) {
        // Clear existing data
        try? context.delete(model: UserSettings.self)
        try? context.delete(model: Cycle.self)
        try? context.delete(model: CompletedWorkout.self)
        try? context.delete(model: WorkoutTemplate.self)
        try? context.delete(model: Exercise.self)

        // Seed exercises and templates
        Exercise.seedDefaults(in: context)
        WorkoutTemplate.seedDefaults(in: context)

        // User settings
        let settings = UserSettings()
        settings.barWeight = 45.0
        settings.roundTo = 5.0
        settings.defaultRestSeconds = 180
        settings.supplementalRestSeconds = 90
        settings.accessoryRestSeconds = 60
        settings.userAge = 32
        settings.bodyWeightLbs = 195
        settings.isMale = true
        settings.appearanceMode = "dark"
        settings.warmupPercentages = [0.40, 0.50, 0.60]
        settings.warmupReps = [5, 5, 3]
        context.insert(settings)

        // Training maxes (intermediate-advanced lifter)
        let cycle1TMs: [String: Double] = [
            "squat": 315,
            "bench": 225,
            "deadlift": 365,
            "overheadPress": 155,
        ]

        let cycle2TMs: [String: Double] = [
            "squat": 325,
            "bench": 230,
            "deadlift": 375,
            "overheadPress": 160,
        ]

        let cycle3TMs: [String: Double] = [
            "squat": 335,
            "bench": 235,
            "deadlift": 385,
            "overheadPress": 165,
        ]

        // Cycle 1 — complete
        let cycle1 = Cycle(
            number: 1,
            startDate: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now)!,
            trainingMaxes: cycle1TMs,
            variant: .boringButBig,
            isComplete: true
        )
        context.insert(cycle1)

        // Cycle 2 — complete
        let cycle2 = Cycle(
            number: 2,
            startDate: Calendar.current.date(byAdding: .weekOfYear, value: -8, to: .now)!,
            trainingMaxes: cycle2TMs,
            variant: .boringButBig,
            isComplete: true
        )
        context.insert(cycle2)

        // Cycle 3 — current (in progress)
        let cycle3 = Cycle(
            number: 3,
            startDate: Calendar.current.date(byAdding: .weekOfYear, value: -3, to: .now)!,
            trainingMaxes: cycle3TMs,
            variant: .boringButBig
        )
        context.insert(cycle3)

        // Generate workout history
        let templates = [
            ("Squat + OHP", "squat", "overheadPress"),
            ("Deadlift + Bench", "deadlift", "bench"),
        ]

        let accessories = [
            ("Barbell Row", false),
            ("Dumbbell Lunges", true),
            ("Face Pull", false),
            ("Tricep Pushdown", false),
            ("Leg Curl", false),
            ("Dumbbell Curl", true),
        ]

        var workoutDate = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now)!

        // Generate 3 cycles × 3 weeks of workouts (skip deload week 4)
        for cycleNum in 1...3 {
            let tms: [String: Double] = cycleNum == 1 ? cycle1TMs : cycleNum == 2 ? cycle2TMs : cycle3TMs
            let weeksToGenerate = cycleNum == 3 ? 2 : 3  // Current cycle only has 2 weeks done

            for week in 1...weeksToGenerate {
                for (templateName, lift1Raw, lift2Raw) in templates {
                    let lift1 = Lift(rawValue: lift1Raw)!
                    let lift2 = Lift(rawValue: lift2Raw)!
                    let tm1 = tms[lift1Raw]!
                    let tm2 = tms[lift2Raw]!

                    let perfs = buildWorkoutPerformances(
                        lift1: lift1, tm1: tm1,
                        lift2: lift2, tm2: tm2,
                        week: week, accessories: accessories
                    )

                    let avgHR = Double.random(in: 125...150)
                    let duration = Int.random(in: 3600...5400)
                    let calories = avgHR * Double(duration) / 60.0 * 0.05

                    let workout = CompletedWorkout(
                        date: workoutDate,
                        templateName: templateName,
                        cycleNumber: cycleNum,
                        weekNumber: week,
                        exercisePerformances: perfs,
                        notes: week == 3 && cycleNum == 2 ? "PR on deadlift AMRAP — felt strong today" : "",
                        durationSeconds: duration,
                        variant: .boringButBig,
                        averageHeartRate: avgHR,
                        estimatedCalories: calories
                    )
                    context.insert(workout)

                    // Space workouts 2-3 days apart
                    workoutDate = Calendar.current.date(byAdding: .day, value: Int.random(in: 2...3), to: workoutDate)!
                }
            }
        }

        try? context.save()
    }

    // MARK: - Helpers

    private static func buildWorkoutPerformances(
        lift1: Lift, tm1: Double,
        lift2: Lift, tm2: Double,
        week: Int,
        accessories: [(String, Bool)]
    ) -> [ExercisePerformance] {
        var perfs: [ExercisePerformance] = []

        // Main lift 1
        perfs.append(buildMainLiftPerformance(lift: lift1, tm: tm1, week: week, sortOrder: 0))

        // Main lift 2
        perfs.append(buildMainLiftPerformance(lift: lift2, tm: tm2, week: week, sortOrder: 1))

        // 2-3 accessories per workout
        let selectedAccessories = Array(accessories.shuffled().prefix(Int.random(in: 2...3)))
        for (i, (name, isUnilateral)) in selectedAccessories.enumerated() {
            let weight = accessoryWeight(for: name)
            var sets: [CompletedSet] = []
            let numSets = Int.random(in: 3...4)
            for _ in 0..<numSets {
                let reps = Int.random(in: 8...15)
                sets.append(CompletedSet(
                    weight: weight,
                    targetReps: reps,
                    actualReps: reps,
                    setType: .accessory,
                    averageHR: Double.random(in: 110...140)
                ))
            }
            perfs.append(ExercisePerformance(
                exerciseName: name,
                sets: sets,
                sortOrder: i + 2,
                isUnilateral: isUnilateral
            ))
        }

        return perfs
    }

    private static func buildMainLiftPerformance(
        lift: Lift, tm: Double, week: Int, sortOrder: Int
    ) -> ExercisePerformance {
        let percentages: [(Double, Int, Bool)]  // (percentage, reps, isAMRAP)
        switch week {
        case 1: percentages = [(0.65, 5, false), (0.75, 5, false), (0.85, 5, true)]
        case 2: percentages = [(0.70, 3, false), (0.80, 3, false), (0.90, 3, true)]
        case 3: percentages = [(0.75, 5, false), (0.85, 3, false), (0.95, 1, true)]
        default: percentages = [(0.40, 5, false), (0.50, 5, false), (0.60, 5, false)]
        }

        var sets: [CompletedSet] = []

        // Warmup sets
        for (pct, reps) in [(0.40, 5), (0.50, 5), (0.60, 3)] {
            let weight = round(tm * pct / 5) * 5
            sets.append(CompletedSet(
                weight: weight,
                targetReps: reps,
                actualReps: reps,
                setType: .warmup,
                averageHR: Double.random(in: 90...110)
            ))
        }

        // Main sets
        for (pct, reps, isAMRAP) in percentages {
            let weight = round(tm * pct / 5) * 5
            let actualReps = isAMRAP ? reps + Int.random(in: 2...6) : reps
            let hr = Double.random(in: 130...165)
            let rpe = 6.0 + (hr / Double(220 - 32) - 0.5) * 10.0
            sets.append(CompletedSet(
                weight: weight,
                targetReps: reps,
                actualReps: actualReps,
                isAMRAP: isAMRAP,
                setType: .main,
                averageHR: hr
            ))
            // Set RPE on the last added set
            sets[sets.count - 1].estimatedRPE = min(10, max(6, rpe))
        }

        // BBB supplemental sets (5x10 @ 50%)
        let bbbWeight = round(tm * 0.50 / 5) * 5
        for _ in 0..<5 {
            sets.append(CompletedSet(
                weight: bbbWeight,
                targetReps: 10,
                actualReps: 10,
                setType: .supplemental,
                averageHR: Double.random(in: 120...145)
            ))
        }

        return ExercisePerformance(
            exerciseName: lift.displayName,
            mainLift: lift.rawValue,
            sets: sets,
            sortOrder: sortOrder
        )
    }

    private static func accessoryWeight(for name: String) -> Double {
        switch name {
        case "Barbell Row": return Double([135, 155, 185].randomElement()!)
        case "Dumbbell Lunges": return 50
        case "Face Pull": return Double([30, 40, 50].randomElement()!)
        case "Tricep Pushdown": return Double([40, 50, 60].randomElement()!)
        case "Leg Curl": return Double([90, 110, 130].randomElement()!)
        case "Dumbbell Curl": return Double([25, 30, 35].randomElement()!)
        default: return 45
        }
    }
}
