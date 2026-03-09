import Foundation
import SwiftData

@Model
final class CompletedWorkout {
    var id: UUID
    var date: Date
    var lift: String  // Lift.rawValue (legacy single-lift field)
    var cycleNumber: Int
    var weekNumber: Int  // 1-4
    var sets: [CompletedSet]
    var accessorySets: [CompletedSet]
    var notes: String
    var durationSeconds: Int
    var variant: String  // ProgramVariant.rawValue
    var templateName: String
    var exercisePerformances: [ExercisePerformance]

    // Legacy single-lift init (kept for backward compatibility and imports)
    init(
        date: Date = .now,
        lift: Lift,
        cycleNumber: Int,
        weekNumber: Int,
        sets: [CompletedSet] = [],
        accessorySets: [CompletedSet] = [],
        notes: String = "",
        durationSeconds: Int = 0,
        variant: ProgramVariant = .standard
    ) {
        self.id = UUID()
        self.date = date
        self.lift = lift.rawValue
        self.cycleNumber = cycleNumber
        self.weekNumber = weekNumber
        self.sets = sets
        self.accessorySets = accessorySets
        self.notes = notes
        self.durationSeconds = durationSeconds
        self.variant = variant.rawValue
        self.templateName = ""
        self.exercisePerformances = []
    }

    // Template-based init for multi-exercise sessions
    init(
        date: Date = .now,
        templateName: String,
        cycleNumber: Int,
        weekNumber: Int,
        exercisePerformances: [ExercisePerformance],
        notes: String = "",
        durationSeconds: Int = 0,
        variant: ProgramVariant = .standard
    ) {
        self.id = UUID()
        self.date = date
        // Use first main lift as the legacy lift field, fallback to squat
        let firstMainLift = exercisePerformances.first(where: { $0.isMainLift })?.mainLift ?? Lift.squat.rawValue
        self.lift = firstMainLift
        self.cycleNumber = cycleNumber
        self.weekNumber = weekNumber
        self.sets = []
        self.accessorySets = []
        self.notes = notes
        self.durationSeconds = durationSeconds
        self.variant = variant.rawValue
        self.templateName = templateName
        self.exercisePerformances = exercisePerformances
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

    /// Unified view of all exercise performances (works for both legacy and new format)
    var allExercisePerformances: [ExercisePerformance] {
        if !exercisePerformances.isEmpty { return exercisePerformances }
        // Legacy fallback: construct from old single-lift fields
        var perf = ExercisePerformance(
            exerciseName: liftType.displayName,
            mainLift: lift,
            sets: sets + accessorySets,
            sortOrder: 0
        )
        perf.id = id  // Stable ID for legacy data
        return [perf]
    }

    /// Display name: template name if available, otherwise lift name
    var displayName: String {
        if !templateName.isEmpty { return templateName }
        return liftType.displayName
    }

    /// The top set (AMRAP) result — key metric for progression tracking
    var topSetReps: Int? {
        // Check new format first
        if !exercisePerformances.isEmpty {
            for perf in exercisePerformances where perf.isMainLift {
                if let amrap = perf.sets.first(where: { $0.isAMRAP }), amrap.actualReps > 0 {
                    return amrap.actualReps
                }
            }
            return nil
        }
        return sets.first(where: { $0.isAMRAP })?.actualReps
    }

    var topSetWeight: Double? {
        if !exercisePerformances.isEmpty {
            for perf in exercisePerformances where perf.isMainLift {
                if let amrap = perf.sets.first(where: { $0.isAMRAP }), amrap.actualReps > 0 {
                    return amrap.weight
                }
            }
            return nil
        }
        return sets.first(where: { $0.isAMRAP })?.weight
    }
}
