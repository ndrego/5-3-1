import Foundation
import SwiftData

/// Handles export and import of all app data as JSON for backup/restore.
struct BackupManager {

    // MARK: - Backup Data Structure

    struct BackupData: Codable {
        let version: Int
        let exportDate: Date
        let cycles: [CycleBackup]
        let workouts: [WorkoutBackup]
        let exercises: [ExerciseBackup]
        let templates: [TemplateBackup]
        let settings: SettingsBackup?

        static let currentVersion = 1
    }

    struct CycleBackup: Codable {
        let number: Int
        let startDate: Date
        let trainingMaxes: [String: Double]
        let variant: String
        let isComplete: Bool
    }

    struct WorkoutBackup: Codable {
        let date: Date
        let lift: String
        let cycleNumber: Int
        let weekNumber: Int
        let notes: String
        let durationSeconds: Int
        let variant: String
        let templateName: String
        let exercisePerformances: [ExercisePerformance]
        let averageHeartRate: Double?
        let estimatedCalories: Double?
    }

    struct ExerciseBackup: Codable {
        let name: String
        let category: String
        let isCustom: Bool
        let equipmentType: String
        let isUnilateral: Bool?
    }

    struct TemplateBackup: Codable {
        let name: String
        let sortOrder: Int
        let exerciseEntries: [TemplateExerciseEntry]
    }

    struct SettingsBackup: Codable {
        let barWeight: Double
        let trainingMaxPercentages: [String: Double]
        let availablePlates: [Double]
        let roundTo: Double
        let defaultRestSeconds: Int
        let supplementalRestSeconds: Int
        let accessoryRestSeconds: Int
        let warmupPercentages: [Double]?
        let warmupReps: [Int]?
        let recoveryHR: Int?
        let userAge: Int?
        let bodyWeightLbs: Double?
        let isMale: Bool?
        let appearanceMode: String?
        let repCountingEnabled: Bool?
        let repSensitivity: [String: Double]?
        let repTempo: [String: Double]?
    }

    // MARK: - Export

    static func exportData(from context: ModelContext) throws -> Data {
        let cycles = try context.fetch(FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.number)]))
        let workouts = try context.fetch(FetchDescriptor<CompletedWorkout>(sortBy: [SortDescriptor(\.date)]))
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let settings = try context.fetch(FetchDescriptor<UserSettings>())

        let backup = BackupData(
            version: BackupData.currentVersion,
            exportDate: .now,
            cycles: cycles.map { c in
                CycleBackup(
                    number: c.number,
                    startDate: c.startDate,
                    trainingMaxes: c.trainingMaxes,
                    variant: c.variant,
                    isComplete: c.isComplete
                )
            },
            workouts: workouts.map { w in
                WorkoutBackup(
                    date: w.date,
                    lift: w.lift,
                    cycleNumber: w.cycleNumber,
                    weekNumber: w.weekNumber,
                    notes: w.notes,
                    durationSeconds: w.durationSeconds,
                    variant: w.variant,
                    templateName: w.templateName,
                    exercisePerformances: w.allExercisePerformances,
                    averageHeartRate: w.averageHeartRate,
                    estimatedCalories: w.estimatedCalories
                )
            },
            exercises: exercises.map { e in
                ExerciseBackup(
                    name: e.name,
                    category: e.category,
                    isCustom: e.isCustom,
                    equipmentType: e.equipmentType,
                    isUnilateral: e.isUnilateral
                )
            },
            templates: templates.map { t in
                TemplateBackup(
                    name: t.name,
                    sortOrder: t.sortOrder,
                    exerciseEntries: t.exerciseEntries
                )
            },
            settings: settings.first.map { s in
                SettingsBackup(
                    barWeight: s.barWeight,
                    trainingMaxPercentages: s.trainingMaxPercentages,
                    availablePlates: s.availablePlates,
                    roundTo: s.roundTo,
                    defaultRestSeconds: s.defaultRestSeconds,
                    supplementalRestSeconds: s.supplementalRestSeconds,
                    accessoryRestSeconds: s.accessoryRestSeconds,
                    warmupPercentages: s.warmupPercentages,
                    warmupReps: s.warmupReps,
                    recoveryHR: s.recoveryHR,
                    userAge: s.userAge,
                    bodyWeightLbs: s.bodyWeightLbs,
                    isMale: s.isMale,
                    appearanceMode: s.appearanceMode,
                    repCountingEnabled: s.repCountingEnabled,
                    repSensitivity: s.repSensitivity,
                    repTempo: s.repTempo
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Generate a filename with the current date
    static func backupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "531-backup-\(formatter.string(from: .now)).json"
    }

    // MARK: - Import

    struct RestoreResult {
        let cycles: Int
        let workouts: Int
        let exercises: Int
        let templates: Int
        let settingsRestored: Bool
    }

    /// Restore data from a backup JSON file. Clears existing data first.
    static func restoreData(from data: Data, context: ModelContext) throws -> RestoreResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        // Clear existing data
        try context.delete(model: CompletedWorkout.self)
        try context.delete(model: Cycle.self)
        try context.delete(model: Exercise.self)
        try context.delete(model: WorkoutTemplate.self)
        try context.delete(model: UserSettings.self)

        // Restore cycles
        for c in backup.cycles {
            let cycle = Cycle(
                number: c.number,
                startDate: c.startDate,
                trainingMaxes: c.trainingMaxes,
                variant: ProgramVariant(rawValue: c.variant) ?? .standard,
                isComplete: c.isComplete
            )
            context.insert(cycle)
        }

        // Restore workouts
        for w in backup.workouts {
            let workout = CompletedWorkout(
                date: w.date,
                templateName: w.templateName,
                cycleNumber: w.cycleNumber,
                weekNumber: w.weekNumber,
                exercisePerformances: w.exercisePerformances,
                notes: w.notes,
                durationSeconds: w.durationSeconds,
                variant: ProgramVariant(rawValue: w.variant) ?? .standard,
                averageHeartRate: w.averageHeartRate,
                estimatedCalories: w.estimatedCalories
            )
            context.insert(workout)
        }

        // Restore exercises
        for e in backup.exercises {
            let exercise = Exercise(
                name: e.name,
                category: ExerciseCategory(rawValue: e.category) ?? .push,
                equipmentType: e.equipmentType,
                isCustom: e.isCustom,
                isUnilateral: e.isUnilateral ?? false
            )
            context.insert(exercise)
        }

        // Restore templates
        for t in backup.templates {
            let template = WorkoutTemplate(
                name: t.name,
                sortOrder: t.sortOrder,
                exerciseEntries: t.exerciseEntries
            )
            context.insert(template)
        }

        // Restore settings
        var settingsRestored = false
        if let s = backup.settings {
            let settings = UserSettings(
                barWeight: s.barWeight,
                trainingMaxPercentages: s.trainingMaxPercentages,
                availablePlates: s.availablePlates,
                roundTo: s.roundTo,
                defaultRestSeconds: s.defaultRestSeconds,
                supplementalRestSeconds: s.supplementalRestSeconds,
                accessoryRestSeconds: s.accessoryRestSeconds,
                warmupPercentages: s.warmupPercentages ?? UserSettings.defaultWarmupPercentages,
                warmupReps: s.warmupReps ?? UserSettings.defaultWarmupReps
            )
            settings.recoveryHR = s.recoveryHR
            settings.userAge = s.userAge
            settings.bodyWeightLbs = s.bodyWeightLbs
            settings.isMale = s.isMale
            settings.appearanceMode = s.appearanceMode
            settings.repCountingEnabled = s.repCountingEnabled
            settings.repSensitivity = s.repSensitivity
            settings.repTempo = s.repTempo
            context.insert(settings)
            settingsRestored = true
        }

        return RestoreResult(
            cycles: backup.cycles.count,
            workouts: backup.workouts.count,
            exercises: backup.exercises.count,
            templates: backup.templates.count,
            settingsRestored: settingsRestored
        )
    }
}
