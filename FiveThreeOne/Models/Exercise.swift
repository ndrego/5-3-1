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
        ("Triceps Dip", .push, "bodyweight"),
        ("Dumbbell Overhead Press", .push, "dumbbell"),
        ("Push-Ups", .push, "bodyweight"),
        ("Tricep Pushdown", .push, "cable"),
        ("Close-Grip Bench Press", .push, "barbell"),
        ("Lateral Raise", .push, "dumbbell"),
        ("Skull Crushers", .push, "barbell"),
        ("Chest Fly", .push, "dumbbell"),

        // Pull
        ("Barbell Row", .pull, "barbell"),
        ("Bent Over Row", .pull, "barbell"),
        ("Dumbbell Row", .pull, "dumbbell"),
        ("Pull-Ups", .pull, "bodyweight"),
        ("Pull Up", .pull, "bodyweight"),
        ("Chin-Ups", .pull, "bodyweight"),
        ("Lat Pulldown", .pull, "cable"),
        ("Face Pulls", .pull, "cable"),
        ("Cable Row", .pull, "cable"),
        ("Seated Row (Cable)", .pull, "cable"),
        ("Reverse Fly (Cable)", .pull, "cable"),
        ("Barbell Curl", .pull, "barbell"),
        ("Dumbbell Curl", .pull, "dumbbell"),
        ("Bicep Curl (Dumbbell)", .pull, "dumbbell"),
        ("Hammer Curl", .pull, "dumbbell"),

        // Single Leg / Core
        ("Bulgarian Split Squat", .singleLegCore, "dumbbell"),
        ("Lunges", .singleLegCore, "dumbbell"),
        ("Romanian Deadlift", .singleLegCore, "barbell"),
        ("Overhead Squat", .singleLegCore, "barbell"),
        ("Front Squat", .singleLegCore, "barbell"),
        ("Leg Press", .singleLegCore, "machine"),
        ("Leg Curl", .singleLegCore, "machine"),
        ("Standing Calf Raise", .singleLegCore, "barbell"),
        ("Ab Wheel", .singleLegCore, "bodyweight"),
        ("Hanging Leg Raise", .singleLegCore, "bodyweight"),
        ("Hanging Knee Raise", .singleLegCore, "bodyweight"),
        ("Plank", .singleLegCore, "bodyweight"),
        ("Side Plank", .singleLegCore, "bodyweight"),
        ("Bicycle Crunch", .singleLegCore, "bodyweight"),
        ("Sit Up", .singleLegCore, "bodyweight"),
        ("Side Bend (Dumbbell)", .singleLegCore, "dumbbell"),
        ("Cable Crunch", .singleLegCore, "cable"),
        ("Back Extension", .singleLegCore, "bodyweight"),
        ("Hip Thrust", .singleLegCore, "barbell"),

        // Olympic
        ("Power Clean", .pull, "barbell"),
        ("Clean and Jerk", .pull, "barbell"),
    ]

    /// Seeds default exercises. Additive — only inserts exercises not already present.
    static func seedDefaults(in context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existing.map { $0.name })

        for (name, category, equipment) in defaultExercises {
            guard !existingNames.contains(name) else { continue }
            context.insert(Exercise(name: name, category: category, equipmentType: equipment))
        }
    }
}
