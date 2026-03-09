import Foundation
import SwiftData

@Model
final class CompletedWorkout {
    var id: UUID
    var date: Date
    var lift: String  // Kept for SwiftData schema compatibility with old data
    var cycleNumber: Int
    var weekNumber: Int  // 1-4
    var sets: [CompletedSet]  // Kept for SwiftData schema compatibility with old data
    var accessorySets: [CompletedSet]  // Kept for SwiftData schema compatibility with old data
    var notes: String
    var durationSeconds: Int
    var variant: String  // ProgramVariant.rawValue
    var templateName: String
    var exercisePerformances: [ExercisePerformance]
    var averageHeartRate: Double?
    var estimatedCalories: Double?

    init(
        date: Date = .now,
        templateName: String,
        cycleNumber: Int,
        weekNumber: Int,
        exercisePerformances: [ExercisePerformance],
        notes: String = "",
        durationSeconds: Int = 0,
        variant: ProgramVariant = .standard,
        averageHeartRate: Double? = nil,
        estimatedCalories: Double? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.lift = exercisePerformances.first(where: { $0.isMainLift })?.mainLift ?? ""
        self.cycleNumber = cycleNumber
        self.weekNumber = weekNumber
        self.sets = []
        self.accessorySets = []
        self.notes = notes
        self.durationSeconds = durationSeconds
        self.variant = variant.rawValue
        self.templateName = templateName
        self.exercisePerformances = exercisePerformances
        self.averageHeartRate = averageHeartRate
        self.estimatedCalories = estimatedCalories
    }

    var liftType: Lift {
        Lift(rawValue: lift) ?? .squat
    }

    var programVariant: ProgramVariant {
        ProgramVariant(rawValue: variant) ?? .standard
    }

    var formattedDuration: String {
        let minutes = durationSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// All exercise performances — migrates old data on read if needed.
    var allExercisePerformances: [ExercisePerformance] {
        if !exercisePerformances.isEmpty { return exercisePerformances }
        // Migrate pre-exercisePerformances data on read
        guard !sets.isEmpty || !accessorySets.isEmpty else { return [] }
        var perf = ExercisePerformance(
            exerciseName: liftType.displayName,
            mainLift: lift,
            sets: sets + accessorySets,
            sortOrder: 0
        )
        perf.id = id
        return [perf]
    }

    var displayName: String {
        if !templateName.isEmpty { return templateName }
        return liftType.displayName
    }

    /// Total training volume across all exercises (weight × reps, excludes warmup)
    var totalVolume: Double {
        allExercisePerformances.reduce(0) { $0 + $1.totalVolume }
    }

    var formattedVolume: String {
        let vol = totalVolume
        if vol >= 1000 {
            return String(format: "%.1fk", vol / 1000)
        }
        return "\(Int(vol))"
    }

    var topSetReps: Int? {
        for perf in allExercisePerformances where perf.isMainLift {
            if let amrap = perf.sets.first(where: { $0.isAMRAP }), amrap.actualReps > 0 {
                return amrap.actualReps
            }
        }
        return nil
    }

    var topSetWeight: Double? {
        for perf in allExercisePerformances where perf.isMainLift {
            if let amrap = perf.sets.first(where: { $0.isAMRAP }), amrap.actualReps > 0 {
                return amrap.weight
            }
        }
        return nil
    }
}
