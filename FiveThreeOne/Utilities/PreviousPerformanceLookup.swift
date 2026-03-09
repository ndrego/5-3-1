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
            if let match = workout.allExercisePerformances.first(where: {
                $0.exerciseName == exerciseName
            }) {
                return match
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

    /// Returns recent top-set weights for a given exercise (for sparkline charts).
    static func recentTopSets(
        exerciseName: String,
        limit: Int = 8,
        in context: ModelContext
    ) -> [(date: Date, weight: Double)] {
        let descriptor = FetchDescriptor<CompletedWorkout>(
            sortBy: [SortDescriptor(\CompletedWorkout.date, order: .reverse)]
        )
        guard let workouts = try? context.fetch(descriptor) else { return [] }

        var results: [(date: Date, weight: Double)] = []

        for workout in workouts {
            guard results.count < limit else { break }
            if let perf = workout.allExercisePerformances.first(where: { $0.exerciseName == exerciseName }),
               let best = perf.bestSet {
                results.append((date: workout.date, weight: best.weight))
            }
        }

        return results.reversed()
    }
}
