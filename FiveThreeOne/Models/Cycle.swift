import Foundation
import SwiftData

@Model
final class Cycle {
    var number: Int
    var startDate: Date
    var trainingMaxes: [String: Double]  // Keyed by Lift.rawValue
    var variant: String  // ProgramVariant.rawValue
    var isComplete: Bool

    init(
        number: Int = 1,
        startDate: Date = .now,
        trainingMaxes: [String: Double] = [:],
        variant: ProgramVariant = .standard,
        isComplete: Bool = false
    ) {
        self.number = number
        self.startDate = startDate
        self.trainingMaxes = trainingMaxes
        self.variant = variant.rawValue
        self.isComplete = isComplete
    }

    var programVariant: ProgramVariant {
        get { ProgramVariant(rawValue: variant) ?? .standard }
        set { variant = newValue.rawValue }
    }

    func trainingMax(for lift: Lift) -> Double {
        trainingMaxes[lift.rawValue] ?? 0
    }

    func setTrainingMax(_ value: Double, for lift: Lift) {
        trainingMaxes[lift.rawValue] = value
    }

    /// Create the next cycle with auto-progressed training maxes
    func nextCycle() -> Cycle {
        var newMaxes: [String: Double] = [:]
        for lift in Lift.allCases {
            let currentTM = trainingMax(for: lift)
            newMaxes[lift.rawValue] = currentTM + lift.progressionIncrement
        }
        return Cycle(
            number: number + 1,
            startDate: .now,
            trainingMaxes: newMaxes,
            variant: programVariant
        )
    }
}
