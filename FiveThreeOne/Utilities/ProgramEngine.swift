import Foundation

/// Pure computation engine for the 5/3/1 program.
/// Given a training max and week number, produces all working sets.
struct ProgramEngine {

    struct PlannedSet: Identifiable {
        let id = UUID()
        let setNumber: Int
        let weight: Double
        let reps: Int
        let percentage: Double
        let isAMRAP: Bool
        let setType: SetType
    }

    // MARK: - Percentages

    /// Main working set percentages per week
    private static let mainPercentages: [[Double]] = [
        [0.65, 0.75, 0.85],                    // Week 1: 5/5/5+
        [0.70, 0.80, 0.90],                    // Week 2: 3/3/3+
        [0.75, 0.85, 0.95],                    // Week 3: 5/3/1+
        [0.40, 0.50, 0.60],                    // Week 4: Deload
        [0.70, 0.80, 0.90, 1.00],              // Week 5: TM Test
        [0.50, 0.60, 0.70, 0.80, 0.90, 1.00],  // Week 6: 1RM Test
    ]

    /// Target reps per set per week
    private static let mainReps: [[Int]] = [
        [5, 5, 5],             // Week 1
        [3, 3, 3],             // Week 2
        [5, 3, 1],             // Week 3
        [5, 5, 5],             // Week 4
        [5, 3, 1, 3],          // Week 5: TM Test — work up to TM for 3-5 reps
        [5, 3, 3, 1, 1, 1],    // Week 6: 1RM Test — work up to true max singles
    ]

    // MARK: - Warmup Sets

    static func warmupSets(
        trainingMax: Double,
        scheme: [(percentage: Double, reps: Int)] = [(0.40, 5), (0.50, 5), (0.60, 3)],
        roundTo: Double = 5.0
    ) -> [PlannedSet] {
        scheme.enumerated().map { i, entry in
            let weight = roundWeight(trainingMax * entry.percentage, to: roundTo)
            return PlannedSet(
                setNumber: i + 1,
                weight: weight,
                reps: entry.reps,
                percentage: entry.percentage,
                isAMRAP: false,
                setType: .warmup
            )
        }
    }

    // MARK: - Main Sets

    static func mainSets(
        trainingMax: Double,
        week: Int,
        variant: ProgramVariant = .standard,
        roundTo: Double = 5.0
    ) -> [PlannedSet] {
        let weekIndex = clampedWeekIndex(week)
        let percentages = mainPercentages[weekIndex]
        let reps = mainReps[weekIndex]
        let isDeload = week == 4
        let isTestWeek = week == 5 || week == 6
        let useAMRAP = variant.hasAMRAP && !isDeload && !isTestWeek

        // For 5s PRO, all sets are 5 reps (not for test weeks)
        let effectiveReps: [Int] = (variant == .fivesPro && !isTestWeek) ? Array(repeating: 5, count: reps.count) : reps

        return (0..<percentages.count).map { i in
            let weight = roundWeight(trainingMax * percentages[i], to: roundTo)
            let isTopSet = (i == percentages.count - 1) && (useAMRAP || isTestWeek)
            return PlannedSet(
                setNumber: i + 1,
                weight: weight,
                reps: effectiveReps[i],
                percentage: percentages[i],
                isAMRAP: isTopSet,
                setType: .main
            )
        }
    }

    // MARK: - Supplemental Sets

    static func supplementalSets(
        trainingMax: Double,
        week: Int,
        variant: ProgramVariant,
        roundTo: Double = 5.0
    ) -> [PlannedSet] {
        // No supplemental work on deload or test weeks
        if week >= 4 { return [] }

        let weekIndex = clampedWeekIndex(week)
        let percentages = mainPercentages[weekIndex]

        switch variant {
        case .standard, .fivesPro:
            return []

        case .boringButBig:
            // 5x10 @ 50% TM (can be progressed to 60% over cycles)
            let weight = roundWeight(trainingMax * 0.50, to: roundTo)
            return (0..<5).map { i in
                PlannedSet(
                    setNumber: i + 1,
                    weight: weight,
                    reps: 10,
                    percentage: 0.50,
                    isAMRAP: false,
                    setType: .supplemental
                )
            }

        case .firstSetLast:
            // 5x5 @ first working set percentage
            let weight = roundWeight(trainingMax * percentages[0], to: roundTo)
            return (0..<5).map { i in
                PlannedSet(
                    setNumber: i + 1,
                    weight: weight,
                    reps: 5,
                    percentage: percentages[0],
                    isAMRAP: false,
                    setType: .supplemental
                )
            }

        case .bbbBeefcake:
            // 5x10 @ first set percentage (harder than standard BBB)
            let weight = roundWeight(trainingMax * percentages[0], to: roundTo)
            return (0..<5).map { i in
                PlannedSet(
                    setNumber: i + 1,
                    weight: weight,
                    reps: 10,
                    percentage: percentages[0],
                    isAMRAP: false,
                    setType: .supplemental
                )
            }

        case .ssl:
            // 5x5 @ second working set percentage
            let weight = roundWeight(trainingMax * percentages[1], to: roundTo)
            return (0..<5).map { i in
                PlannedSet(
                    setNumber: i + 1,
                    weight: weight,
                    reps: 5,
                    percentage: percentages[1],
                    isAMRAP: false,
                    setType: .supplemental
                )
            }
        }
    }

    // MARK: - Joker Sets

    /// Optional joker sets: heavier singles/doubles above the top set
    static func jokerSets(
        trainingMax: Double,
        week: Int,
        count: Int = 2,
        roundTo: Double = 5.0
    ) -> [PlannedSet] {
        let weekIndex = clampedWeekIndex(week)
        let topPercentage = mainPercentages[weekIndex][2]

        return (1...count).map { i in
            let percentage = topPercentage + (0.05 * Double(i))
            let weight = roundWeight(trainingMax * percentage, to: roundTo)
            return PlannedSet(
                setNumber: i,
                weight: weight,
                reps: 1,
                percentage: percentage,
                isAMRAP: false,
                setType: .joker
            )
        }
    }

    // MARK: - Full Workout

    /// Generate all planned sets for a workout (warmup + main + supplemental)
    static func allSets(
        trainingMax: Double,
        week: Int,
        variant: ProgramVariant,
        roundTo: Double = 5.0
    ) -> [PlannedSet] {
        let warmup = warmupSets(trainingMax: trainingMax, roundTo: roundTo)
        let main = mainSets(trainingMax: trainingMax, week: week, variant: variant, roundTo: roundTo)
        let supplemental = supplementalSets(trainingMax: trainingMax, week: week, variant: variant, roundTo: roundTo)
        return warmup + main + supplemental
    }

    // MARK: - Estimated 1RM (Epley formula)

    static func estimated1RM(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    // MARK: - Helpers

    private static func clampedWeekIndex(_ week: Int) -> Int {
        max(0, min(5, week - 1))
    }

    private static func roundWeight(_ weight: Double, to nearest: Double) -> Double {
        (weight / nearest).rounded() * nearest
    }

    /// Week display string
    static func weekLabel(_ week: Int) -> String {
        switch week {
        case 1: return "5/5/5+"
        case 2: return "3/3/3+"
        case 3: return "5/3/1+"
        case 4: return "Deload"
        case 5: return "TM Test"
        case 6: return "1RM Test"
        default: return "Week \(week)"
        }
    }
}
