import Foundation

/// A group of sets for one exercise within a completed workout session.
/// Stored as a Codable array inside CompletedWorkout (same pattern as CompletedSet).
struct ExercisePerformance: Codable, Identifiable, Hashable {
    var id: UUID
    var exerciseName: String
    var mainLift: String?  // Lift.rawValue if 5/3/1 lift
    var sets: [CompletedSet]
    var sortOrder: Int
    var supersetGroup: Int?

    init(
        exerciseName: String,
        mainLift: String? = nil,
        sets: [CompletedSet] = [],
        sortOrder: Int = 0,
        supersetGroup: Int? = nil
    ) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.mainLift = mainLift
        self.sets = sets
        self.sortOrder = sortOrder
        self.supersetGroup = supersetGroup
    }

    var isMainLift: Bool { mainLift != nil }
    var lift: Lift? { mainLift.flatMap { Lift(rawValue: $0) } }

    /// Best set by weight, then by reps
    var bestSet: CompletedSet? {
        sets.filter { $0.isComplete }.max { a, b in
            if a.weight == b.weight { return a.actualReps < b.actualReps }
            return a.weight < b.weight
        }
    }

    /// Summary string like "135 lbs x 5"
    var bestSetSummary: String? {
        guard let best = bestSet else { return nil }
        return "\(Int(best.weight)) lbs x \(best.actualReps)"
    }
}
