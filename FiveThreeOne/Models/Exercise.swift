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
    var isTimed: Bool?         // Timed exercise (e.g. plank) — targetReps = seconds

    init(name: String, category: ExerciseCategory, equipmentType: String = "barbell", isCustom: Bool = false, isUnilateral: Bool = false, isTimed: Bool = false) {
        self.name = name
        self.category = category.rawValue
        self.equipmentType = equipmentType
        self.isCustom = isCustom
        self.isUnilateral = isUnilateral
        self.isTimed = isTimed
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
    //                                                          unilateral, timed
    static let defaultExercises: [(String, ExerciseCategory, String, Bool, Bool)] = [
        // Push
        ("Dumbbell Bench Press", .push, "dumbbell", false, false),
        ("Incline Dumbbell Press", .push, "dumbbell", false, false),
        ("Dips", .push, "bodyweight", false, false),
        ("Triceps Dip", .push, "bodyweight", false, false),
        ("Dumbbell Overhead Press", .push, "dumbbell", false, false),
        ("Push-Ups", .push, "bodyweight", false, false),
        ("Tricep Pushdown", .push, "cable", false, false),
        ("Close-Grip Bench Press", .push, "barbell", false, false),
        ("Lateral Raise", .push, "dumbbell", false, false),
        ("Skull Crushers", .push, "barbell", false, false),
        ("Chest Fly", .push, "dumbbell", false, false),

        // Pull
        ("Barbell Row", .pull, "barbell", false, false),
        ("Bent Over Row", .pull, "barbell", false, false),
        ("Dumbbell Row", .pull, "dumbbell", true, false),
        ("Pull-Ups", .pull, "bodyweight", false, false),
        ("Pull Up", .pull, "bodyweight", false, false),
        ("Chin-Ups", .pull, "bodyweight", false, false),
        ("Lat Pulldown", .pull, "cable", false, false),
        ("Face Pulls", .pull, "cable", false, false),
        ("Cable Row", .pull, "cable", false, false),
        ("Seated Row (Cable)", .pull, "cable", false, false),
        ("Reverse Fly (Cable)", .pull, "cable", false, false),
        ("Barbell Curl", .pull, "barbell", false, false),
        ("Dumbbell Curl", .pull, "dumbbell", true, false),
        ("Bicep Curl (Dumbbell)", .pull, "dumbbell", true, false),
        ("Hammer Curl", .pull, "dumbbell", true, false),

        // Single Leg / Core
        ("Bulgarian Split Squat", .singleLegCore, "barbell", true, false),
        ("Lunges", .singleLegCore, "dumbbell", true, false),
        ("Romanian Deadlift", .singleLegCore, "barbell", false, false),
        ("Overhead Squat", .singleLegCore, "barbell", false, false),
        ("Front Squat", .singleLegCore, "barbell", false, false),
        ("Leg Press", .singleLegCore, "machine", false, false),
        ("Leg Curl", .singleLegCore, "machine", false, false),
        ("Standing Calf Raise", .singleLegCore, "barbell", false, false),
        ("Ab Wheel", .singleLegCore, "bodyweight", false, false),
        ("Ab Rollout (Stability Ball)", .singleLegCore, "other", false, false),
        ("Plank Pull-Through (Kettlebell)", .singleLegCore, "other", false, false),
        ("Hanging Leg Raise", .singleLegCore, "bodyweight", false, false),
        ("Hanging Knee Raise", .singleLegCore, "bodyweight", false, false),
        ("Plank", .singleLegCore, "bodyweight", false, true),
        ("Side Plank", .singleLegCore, "bodyweight", true, true),
        ("Bicycle Crunch", .singleLegCore, "bodyweight", false, false),
        ("Sit Up", .singleLegCore, "bodyweight", false, false),
        ("Side Bend (Dumbbell)", .singleLegCore, "dumbbell", true, false),
        ("Cable Crunch", .singleLegCore, "cable", false, false),
        ("Back Extension", .singleLegCore, "bodyweight", false, false),
        ("Hip Thrust", .singleLegCore, "barbell", false, false),

        // Olympic
        ("Power Clean", .pull, "barbell", false, false),
        ("Clean and Jerk", .pull, "barbell", false, false),
    ]

    /// Seeds default exercises. Additive — only inserts exercises not already present.
    /// Updates isUnilateral for existing exercises if not yet set.
    static func seedDefaults(in context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingByName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        for (name, category, equipment, unilateral, timed) in defaultExercises {
            if let ex = existingByName[name] {
                if ex.isUnilateral == nil {
                    ex.isUnilateral = unilateral
                }
                if timed && ex.isTimed != true {
                    ex.isTimed = true
                }
            } else {
                context.insert(Exercise(name: name, category: category, equipmentType: equipment, isUnilateral: unilateral, isTimed: timed))
            }
        }
    }
}
