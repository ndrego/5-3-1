import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var sortOrder: Int
    var exerciseEntries: [TemplateExerciseEntry]

    init(
        name: String,
        sortOrder: Int = 0,
        exerciseEntries: [TemplateExerciseEntry] = []
    ) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.exerciseEntries = exerciseEntries
    }

    /// The main 5/3/1 lifts in this template
    var mainLifts: [Lift] {
        exerciseEntries.compactMap { $0.lift }
    }

    static func seedDefaults(in context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutTemplate>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let templates = [
            WorkoutTemplate(
                name: "Deadlift + Bench",
                sortOrder: 0,
                exerciseEntries: [
                    TemplateExerciseEntry(exerciseName: "Deadlift", mainLift: Lift.deadlift.rawValue, sortOrder: 0),
                    TemplateExerciseEntry(exerciseName: "Bench Press", mainLift: Lift.bench.rawValue, sortOrder: 1),
                    TemplateExerciseEntry(exerciseName: "Triceps Dip", sortOrder: 2),
                    TemplateExerciseEntry(exerciseName: "Bicep Curl (Dumbbell)", sortOrder: 3),
                    TemplateExerciseEntry(exerciseName: "Bent Over Row", sortOrder: 4),
                ]
            ),
            WorkoutTemplate(
                name: "Squat + OHP",
                sortOrder: 1,
                exerciseEntries: [
                    TemplateExerciseEntry(exerciseName: "Squat", mainLift: Lift.squat.rawValue, sortOrder: 0),
                    TemplateExerciseEntry(exerciseName: "Overhead Press", mainLift: Lift.overheadPress.rawValue, sortOrder: 1),
                    TemplateExerciseEntry(exerciseName: "Plank", sortOrder: 2),
                    TemplateExerciseEntry(exerciseName: "Side Plank", sortOrder: 3),
                    TemplateExerciseEntry(exerciseName: "Bicycle Crunch", sortOrder: 4),
                    TemplateExerciseEntry(exerciseName: "Sit Up", sortOrder: 5),
                    TemplateExerciseEntry(exerciseName: "Side Bend (Dumbbell)", sortOrder: 6),
                ]
            ),
            WorkoutTemplate(
                name: "RDL + Split Squats",
                sortOrder: 2,
                exerciseEntries: [
                    TemplateExerciseEntry(exerciseName: "Bulgarian Split Squat", sortOrder: 0),
                    TemplateExerciseEntry(exerciseName: "Romanian Deadlift", sortOrder: 1),
                    TemplateExerciseEntry(exerciseName: "Overhead Squat", sortOrder: 2),
                    TemplateExerciseEntry(exerciseName: "Pull Up", sortOrder: 3),
                    TemplateExerciseEntry(exerciseName: "Hanging Knee Raise", sortOrder: 4),
                    TemplateExerciseEntry(exerciseName: "Seated Row (Cable)", sortOrder: 5),
                ]
            ),
            WorkoutTemplate(
                name: "Power Cleaning Fun",
                sortOrder: 3,
                exerciseEntries: [
                    TemplateExerciseEntry(exerciseName: "Power Clean", sortOrder: 0),
                    TemplateExerciseEntry(exerciseName: "Clean and Jerk", sortOrder: 1),
                    TemplateExerciseEntry(exerciseName: "Chest Fly", sortOrder: 2),
                    TemplateExerciseEntry(exerciseName: "Reverse Fly (Cable)", sortOrder: 3),
                    TemplateExerciseEntry(exerciseName: "Standing Calf Raise", sortOrder: 4),
                    TemplateExerciseEntry(exerciseName: "Back Extension", sortOrder: 5),
                    TemplateExerciseEntry(exerciseName: "Front Squat", sortOrder: 6),
                ]
            ),
        ]

        for template in templates {
            context.insert(template)
        }
    }
}

struct TemplateExerciseEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var exerciseName: String
    var mainLift: String?  // Lift.rawValue if this is a 5/3/1 lift, nil for accessories
    var sortOrder: Int
    var supersetGroup: Int?  // Exercises with same non-nil value are supersetted

    init(exerciseName: String, mainLift: String? = nil, sortOrder: Int = 0, supersetGroup: Int? = nil) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.mainLift = mainLift
        self.sortOrder = sortOrder
        self.supersetGroup = supersetGroup
    }

    var isMainLift: Bool { mainLift != nil }

    var lift: Lift? { mainLift.flatMap { Lift(rawValue: $0) } }
}
