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
    var isUnilateral: Bool?    // Single-arm/leg exercise — volume doubled for total

    init(name: String, category: ExerciseCategory, equipmentType: String = "barbell", isCustom: Bool = false, isUnilateral: Bool = false) {
        self.name = name
        self.category = category.rawValue
        self.equipmentType = equipmentType
        self.isCustom = isCustom
        self.isUnilateral = isUnilateral
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
    static let defaultExercises: [(String, ExerciseCategory, String, Bool)] = [
        // Push                                                    unilateral
        ("Dumbbell Bench Press", .push, "dumbbell", false),
        ("Incline Dumbbell Press", .push, "dumbbell", false),
        ("Dips", .push, "bodyweight", false),
        ("Triceps Dip", .push, "bodyweight", false),
        ("Dumbbell Overhead Press", .push, "dumbbell", false),
        ("Push-Ups", .push, "bodyweight", false),
        ("Tricep Pushdown", .push, "cable", false),
        ("Close-Grip Bench Press", .push, "barbell", false),
        ("Lateral Raise", .push, "dumbbell", false),
        ("Skull Crushers", .push, "barbell", false),
        ("Chest Fly", .push, "dumbbell", false),

        // Pull
        ("Barbell Row", .pull, "barbell", false),
        ("Bent Over Row", .pull, "barbell", false),
        ("Dumbbell Row", .pull, "dumbbell", true),
        ("Pull-Ups", .pull, "bodyweight", false),
        ("Pull Up", .pull, "bodyweight", false),
        ("Chin-Ups", .pull, "bodyweight", false),
        ("Lat Pulldown", .pull, "cable", false),
        ("Face Pulls", .pull, "cable", false),
        ("Cable Row", .pull, "cable", false),
        ("Seated Row (Cable)", .pull, "cable", false),
        ("Reverse Fly (Cable)", .pull, "cable", false),
        ("Barbell Curl", .pull, "barbell", false),
        ("Dumbbell Curl", .pull, "dumbbell", true),
        ("Bicep Curl (Dumbbell)", .pull, "dumbbell", true),
        ("Hammer Curl", .pull, "dumbbell", true),

        // Single Leg / Core
        ("Bulgarian Split Squat", .singleLegCore, "barbell", true),
        ("Lunges", .singleLegCore, "dumbbell", true),
        ("Romanian Deadlift", .singleLegCore, "barbell", false),
        ("Overhead Squat", .singleLegCore, "barbell", false),
        ("Front Squat", .singleLegCore, "barbell", false),
        ("Leg Press", .singleLegCore, "machine", false),
        ("Leg Curl", .singleLegCore, "machine", false),
        ("Standing Calf Raise", .singleLegCore, "barbell", false),
        ("Ab Wheel", .singleLegCore, "bodyweight", false),
        ("Hanging Leg Raise", .singleLegCore, "bodyweight", false),
        ("Hanging Knee Raise", .singleLegCore, "bodyweight", false),
        ("Plank", .singleLegCore, "bodyweight", false),
        ("Side Plank", .singleLegCore, "bodyweight", true),
        ("Bicycle Crunch", .singleLegCore, "bodyweight", false),
        ("Sit Up", .singleLegCore, "bodyweight", false),
        ("Side Bend (Dumbbell)", .singleLegCore, "dumbbell", true),
        ("Cable Crunch", .singleLegCore, "cable", false),
        ("Back Extension", .singleLegCore, "bodyweight", false),
        ("Hip Thrust", .singleLegCore, "barbell", false),

        // Olympic
        ("Power Clean", .pull, "barbell", false),
        ("Clean and Jerk", .pull, "barbell", false),
    ]

    /// Seeds default exercises. Additive — only inserts exercises not already present.
    /// Updates isUnilateral for existing exercises if not yet set.
    static func seedDefaults(in context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingByName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        for (name, category, equipment, unilateral) in defaultExercises {
            if let ex = existingByName[name] {
                if ex.isUnilateral == nil {
                    ex.isUnilateral = unilateral
                }
            } else {
                context.insert(Exercise(name: name, category: category, equipmentType: equipment, isUnilateral: unilateral))
            }
        }
    }
}
