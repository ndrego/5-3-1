import Foundation

enum Lift: String, Codable, CaseIterable, Identifiable {
    case squat
    case bench
    case deadlift
    case overheadPress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squat: return "Squat"
        case .bench: return "Bench Press"
        case .deadlift: return "Deadlift"
        case .overheadPress: return "Overhead Press"
        }
    }

    var shortName: String {
        switch self {
        case .squat: return "SQ"
        case .bench: return "BP"
        case .deadlift: return "DL"
        case .overheadPress: return "OHP"
        }
    }

    var isUpperBody: Bool {
        self == .bench || self == .overheadPress
    }

    /// Progression increment per cycle in lbs
    var progressionIncrement: Double {
        isUpperBody ? 5.0 : 10.0
    }

    /// Common Strong app exercise names that map to this lift
    var strongAppNames: [String] {
        switch self {
        case .squat: return ["Squat (Barbell)", "Back Squat (Barbell)", "Barbell Squat"]
        case .bench: return ["Bench Press (Barbell)", "Barbell Bench Press", "Flat Barbell Bench Press"]
        case .deadlift: return ["Deadlift (Barbell)", "Barbell Deadlift", "Conventional Deadlift (Barbell)"]
        case .overheadPress: return ["Overhead Press (Barbell)", "Barbell Overhead Press", "Standing Barbell Overhead Press", "Shoulder Press (Barbell)"]
        }
    }

    static func fromStrongName(_ name: String) -> Lift? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        for lift in Lift.allCases {
            for strongName in lift.strongAppNames {
                if strongName.lowercased() == normalized {
                    return lift
                }
            }
        }
        return nil
    }
}
