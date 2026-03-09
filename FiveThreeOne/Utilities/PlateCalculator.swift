import Foundation

struct PlateCalculator {

    struct PlateResult {
        let plates: [Double]     // Plates for ONE side of the bar
        let totalWeight: Double  // Actual loaded weight (may differ from target due to rounding)
        let targetWeight: Double

        var isExact: Bool { totalWeight == targetWeight }

        /// Human-readable plate description for one side
        var description: String {
            if plates.isEmpty { return "Empty bar" }
            let grouped = Dictionary(grouping: plates, by: { $0 })
                .sorted { $0.key > $1.key }
                .map { plate, count in
                    count.count > 1 ? "\(count.count)×\(formatWeight(plate))" : formatWeight(plate)
                }
            return grouped.joined(separator: " + ")
        }

        private func formatWeight(_ w: Double) -> String {
            w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
        }
    }

    /// Calculate plates needed per side for a given total weight.
    /// Uses a greedy algorithm with available plates sorted descending.
    static func calculate(
        totalWeight: Double,
        barWeight: Double = 45.0,
        availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5]
    ) -> PlateResult {
        let weightPerSide = (totalWeight - barWeight) / 2.0

        guard weightPerSide > 0 else {
            return PlateResult(plates: [], totalWeight: barWeight, targetWeight: totalWeight)
        }

        let sorted = availablePlates.sorted(by: >)
        var remaining = weightPerSide
        var plates: [Double] = []

        for plate in sorted {
            while remaining >= plate {
                plates.append(plate)
                remaining -= plate
            }
        }

        let actualPerSide = plates.reduce(0, +)
        let actualTotal = barWeight + (actualPerSide * 2)

        return PlateResult(plates: plates, totalWeight: actualTotal, targetWeight: totalWeight)
    }
}
