import Foundation
import SwiftData

@Model
final class UserSettings {
    var barWeight: Double
    var trainingMaxPercentages: [String: Double]  // Per-lift TM%, keyed by Lift.rawValue
    var availablePlates: [Double]
    var roundTo: Double
    var defaultRestSeconds: Int       // Main sets
    var supplementalRestSeconds: Int  // BBB/FSL sets
    var accessoryRestSeconds: Int
    var warmupPercentages: [Double]?  // e.g. [0.40, 0.50, 0.60]
    var warmupReps: [Int]?            // e.g. [5, 5, 3] — parallel to warmupPercentages
    var recoveryHR: Int?              // Target HR for rest recovery (nil = disabled)

    static let defaultWarmupPercentages: [Double] = [0.40, 0.50, 0.60]
    static let defaultWarmupReps: [Int] = [5, 5, 3]

    init(
        barWeight: Double = 45.0,
        trainingMaxPercentages: [String: Double] = [:],
        availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5],
        roundTo: Double = 5.0,
        defaultRestSeconds: Int = 180,
        supplementalRestSeconds: Int = 90,
        accessoryRestSeconds: Int = 60,
        warmupPercentages: [Double] = defaultWarmupPercentages,
        warmupReps: [Int] = defaultWarmupReps
    ) {
        self.barWeight = barWeight
        self.trainingMaxPercentages = trainingMaxPercentages
        self.availablePlates = availablePlates
        self.roundTo = roundTo
        self.defaultRestSeconds = defaultRestSeconds
        self.supplementalRestSeconds = supplementalRestSeconds
        self.accessoryRestSeconds = accessoryRestSeconds
        self.warmupPercentages = warmupPercentages
        self.warmupReps = warmupReps
    }

    var effectiveWarmupPercentages: [Double] {
        get { warmupPercentages ?? Self.defaultWarmupPercentages }
        set { warmupPercentages = newValue }
    }

    var effectiveWarmupReps: [Int] {
        get { warmupReps ?? Self.defaultWarmupReps }
        set { warmupReps = newValue }
    }

    var warmupScheme: [(percentage: Double, reps: Int)] {
        zip(effectiveWarmupPercentages, effectiveWarmupReps).map { ($0, $1) }
    }

    func tmPercentage(for lift: Lift) -> Double {
        trainingMaxPercentages[lift.rawValue] ?? 0.90
    }

    func setTmPercentage(_ value: Double, for lift: Lift) {
        trainingMaxPercentages[lift.rawValue] = value
    }

    func roundWeight(_ weight: Double) -> Double {
        (weight / roundTo).rounded() * roundTo
    }
}
