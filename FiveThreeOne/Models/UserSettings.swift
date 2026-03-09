import Foundation
import SwiftData

@Model
final class UserSettings {
    var barWeight: Double
    var trainingMaxPercentage: Double
    var availablePlates: [Double]
    var roundTo: Double
    var defaultRestSeconds: Int       // Main sets
    var supplementalRestSeconds: Int  // BBB/FSL sets
    var accessoryRestSeconds: Int

    init(
        barWeight: Double = 45.0,
        trainingMaxPercentage: Double = 0.90,
        availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5],
        roundTo: Double = 5.0,
        defaultRestSeconds: Int = 180,
        supplementalRestSeconds: Int = 90,
        accessoryRestSeconds: Int = 60
    ) {
        self.barWeight = barWeight
        self.trainingMaxPercentage = trainingMaxPercentage
        self.availablePlates = availablePlates
        self.roundTo = roundTo
        self.defaultRestSeconds = defaultRestSeconds
        self.supplementalRestSeconds = supplementalRestSeconds
        self.accessoryRestSeconds = accessoryRestSeconds
    }

    func roundWeight(_ weight: Double) -> Double {
        (weight / roundTo).rounded() * roundTo
    }
}
