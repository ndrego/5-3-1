import Foundation
import SwiftData

/// Finds the most recent performance for a given exercise across all completed workouts.
struct PreviousPerformanceLookup {

    /// Returns the most recent ExercisePerformance for the given exercise name.
    static func lastPerformance(
        exerciseName: String,
        in context: ModelContext
    ) -> ExercisePerformance? {
        let descriptor = FetchDescriptor<CompletedWorkout>(
            sortBy: [SortDescriptor(\CompletedWorkout.date, order: .reverse)]
        )
        guard let workouts = try? context.fetch(descriptor) else { return nil }

        for workout in workouts {
            // Check new multi-exercise format
            if !workout.exercisePerformances.isEmpty {
                if let match = workout.exercisePerformances.first(where: {
                    $0.exerciseName == exerciseName
                }) {
                    return match
                }
            }
            // Check legacy format: match by lift display name
            if workout.templateName.isEmpty && workout.liftType.displayName == exerciseName {
                let sets = workout.sets + workout.accessorySets
                guard !sets.isEmpty else { continue }
                return ExercisePerformance(
                    exerciseName: exerciseName,
                    mainLift: workout.lift,
                    sets: sets,
                    sortOrder: 0
                )
            }
        }
        return nil
    }

    /// Returns the most recent performance for a main lift by Lift enum.
    static func lastPerformance(
        lift: Lift,
        in context: ModelContext
    ) -> ExercisePerformance? {
        lastPerformance(exerciseName: lift.displayName, in: context)
    }
}
