import Foundation
import SwiftData

/// Represents an exercise in the exercise library.
/// The four main lifts are handled separately via the Lift enum;
/// this model is for accessory/assistance exercises.
@Model
final class Exercise {
    var name: String
    var category: String  // ExerciseCategory.rawValue
    var isCustom: Bool
    var equipmentType: String  // e.g. "barbell", "dumbbell", "cable", "bodyweight"

    init(name: String, category: ExerciseCategory, equipmentType: String = "barbell", isCustom: Bool = false) {
        self.name = name
        self.category = category.rawValue
        self.equipmentType = equipmentType
        self.isCustom = isCustom
    }

    var exerciseCategory: ExerciseCategory {
        ExerciseCategory(rawValue: category) ?? .push
    }
}

/// 5/3/1 assistance categories
enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case push
    case pull
    case singleLegCore  // Single leg / core work

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .singleLegCore: return "Single Leg / Core"
        }
    }
}

/// Default exercise library — common accessories for 5/3/1
extension Exercise {
    static let defaultExercises: [(String, ExerciseCategory, String)] = [
        // Push
        ("Dumbbell Bench Press", .push, "dumbbell"),
        ("Incline Dumbbell Press", .push, "dumbbell"),
        ("Dips", .push, "bodyweight"),
        ("Dumbbell Overhead Press", .push, "dumbbell"),
        ("Push-Ups", .push, "bodyweight"),
        ("Tricep Pushdown", .push, "cable"),
        ("Close-Grip Bench Press", .push, "barbell"),
        ("Lateral Raise", .push, "dumbbell"),
        ("Skull Crushers", .push, "barbell"),

        // Pull
        ("Barbell Row", .pull, "barbell"),
        ("Dumbbell Row", .pull, "dumbbell"),
        ("Pull-Ups", .pull, "bodyweight"),
        ("Chin-Ups", .pull, "bodyweight"),
        ("Lat Pulldown", .pull, "cable"),
        ("Face Pulls", .pull, "cable"),
        ("Cable Row", .pull, "cable"),
        ("Barbell Curl", .pull, "barbell"),
        ("Dumbbell Curl", .pull, "dumbbell"),
        ("Hammer Curl", .pull, "dumbbell"),

        // Single Leg / Core
        ("Bulgarian Split Squat", .singleLegCore, "dumbbell"),
        ("Lunges", .singleLegCore, "dumbbell"),
        ("Romanian Deadlift", .singleLegCore, "barbell"),
        ("Leg Press", .singleLegCore, "machine"),
        ("Leg Curl", .singleLegCore, "machine"),
        ("Ab Wheel", .singleLegCore, "bodyweight"),
        ("Hanging Leg Raise", .singleLegCore, "bodyweight"),
        ("Plank", .singleLegCore, "bodyweight"),
        ("Cable Crunch", .singleLegCore, "cable"),
        ("Back Extension", .singleLegCore, "bodyweight"),
        ("Hip Thrust", .singleLegCore, "barbell"),
    ]

    static func seedDefaults(in context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for (name, category, equipment) in defaultExercises {
            context.insert(Exercise(name: name, category: category, equipmentType: equipment))
        }
    }
}
