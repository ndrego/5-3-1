import Foundation
import SwiftData

@Model
final class CompletedWorkout {
    var id: UUID
    var date: Date
    var lift: String  // Lift.rawValue
    var cycleNumber: Int
    var weekNumber: Int  // 1-4
    var sets: [CompletedSet]
    var accessorySets: [CompletedSet]
    var notes: String
    var durationSeconds: Int
    var variant: String  // ProgramVariant.rawValue

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

    /// The top set (AMRAP) result — key metric for progression tracking
    var topSetReps: Int? {
        sets.first(where: { $0.isAMRAP })?.actualReps
    }

    var topSetWeight: Double? {
        sets.first(where: { $0.isAMRAP })?.weight
    }
}
