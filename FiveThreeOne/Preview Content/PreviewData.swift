import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static let sampleTrainingMaxes: [String: Double] = [
        "squat": 315,
        "bench": 225,
        "deadlift": 365,
        "overheadPress": 145,
    ]

    static var sampleCycle: Cycle {
        Cycle(
            number: 1,
            trainingMaxes: sampleTrainingMaxes,
            variant: .boringButBig
        )
    }

    static var sampleWorkout: CompletedWorkout {
        CompletedWorkout(
            date: .now,
            templateName: "Squat Day",
            cycleNumber: 1,
            weekNumber: 1,
            exercisePerformances: [
                ExercisePerformance(
                    exerciseName: "Squat",
                    mainLift: Lift.squat.rawValue,
                    sets: [
                        CompletedSet(weight: 205, targetReps: 5, actualReps: 5),
                        CompletedSet(weight: 235, targetReps: 5, actualReps: 5),
                        CompletedSet(weight: 270, targetReps: 5, actualReps: 8, isAMRAP: true),
                    ],
                    sortOrder: 0
                )
            ]
        )
    }

    static var previewContainer: ModelContainer {
        let schema = Schema([Cycle.self, CompletedWorkout.self, UserSettings.self, Exercise.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])

        let context = container.mainContext
        context.insert(sampleCycle)
        context.insert(sampleWorkout)
        context.insert(UserSettings())

        return container
    }
}
