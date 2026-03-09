import Foundation
import SwiftData

/// Imports workout history from the Strong app's CSV export format.
///
/// Strong CSV columns:
/// Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE
struct StrongImporter {

    struct ImportResult {
        let workoutsImported: Int
        let setsImported: Int
        let exercisesFound: Set<String>
        let unmappedExercises: Set<String>  // Exercises that couldn't be mapped to a Lift
        let errors: [String]
    }

    struct StrongRow {
        let date: Date
        let workoutName: String
        let duration: String
        let exerciseName: String
        let setOrder: Int
        let weight: Double
        let reps: Int
        let distance: Double
        let seconds: Int
        let notes: String
        let workoutNotes: String
        let rpe: Double?
    }

    // MARK: - Parsing

    static func parseCSV(_ csvString: String) -> ([StrongRow], [String]) {
        var rows: [StrongRow] = []
        var errors: [String] = []

        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            return ([], ["CSV file is empty or has no data rows"])
        }

        // Skip header line
        for (lineIndex, line) in lines.dropFirst().enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let fields = parseCSVLine(trimmed)
            guard fields.count >= 7 else {
                errors.append("Line \(lineIndex + 2): expected at least 7 fields, got \(fields.count)")
                continue
            }

            guard let date = parseDate(fields[0]) else {
                errors.append("Line \(lineIndex + 2): invalid date '\(fields[0])'")
                continue
            }

            let row = StrongRow(
                date: date,
                workoutName: fields[1],
                duration: fields[2],
                exerciseName: fields[3],
                setOrder: Int(fields[4]) ?? 1,
                weight: Double(fields[5]) ?? 0,
                reps: Int(fields[6]) ?? 0,
                distance: fields.count > 7 ? Double(fields[7]) ?? 0 : 0,
                seconds: fields.count > 8 ? Int(fields[8]) ?? 0 : 0,
                notes: fields.count > 9 ? fields[9] : "",
                workoutNotes: fields.count > 10 ? fields[10] : "",
                rpe: fields.count > 11 ? Double(fields[11]) : nil
            )
            rows.append(row)
        }

        return (rows, errors)
    }

    /// Parse a CSV line respecting quoted fields
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    // MARK: - Import

    /// Import Strong CSV data into the app's data store.
    /// Only imports sets for exercises that map to a 5/3/1 main lift.
    /// Returns all found exercises so the user can see what was in their data.
    static func importCSV(_ csvString: String, context: ModelContext) -> ImportResult {
        let (rows, parseErrors) = parseCSV(csvString)

        var allExercises: Set<String> = []
        var unmapped: Set<String> = []
        var workoutCount = 0
        var setCount = 0

        // Group rows by date + exercise name to reconstruct workouts
        struct WorkoutKey: Hashable {
            let date: Date
            let exerciseName: String
        }

        var grouped: [WorkoutKey: [StrongRow]] = [:]
        for row in rows {
            allExercises.insert(row.exerciseName)
            let key = WorkoutKey(date: row.date, exerciseName: row.exerciseName)
            grouped[key, default: []].append(row)
        }

        // Sort groups by set order
        for key in grouped.keys {
            grouped[key]?.sort { $0.setOrder < $1.setOrder }
        }

        // Import each workout group
        for (key, setRows) in grouped.sorted(by: { $0.key.date < $1.key.date }) {
            guard let lift = Lift.fromStrongName(key.exerciseName) else {
                unmapped.insert(key.exerciseName)
                continue
            }

            let sets = setRows.map { row in
                CompletedSet(
                    weight: row.weight,
                    targetReps: row.reps,
                    actualReps: row.reps,
                    isAMRAP: false,
                    setType: .main
                )
            }

            let notes = setRows.first(where: { !$0.workoutNotes.isEmpty })?.workoutNotes ?? ""

            let perf = ExercisePerformance(
                exerciseName: lift.displayName,
                mainLift: lift.rawValue,
                sets: sets,
                sortOrder: 0
            )

            // We don't know the original cycle/week, so mark as cycle 0
            let workout = CompletedWorkout(
                date: key.date,
                templateName: lift.displayName,
                cycleNumber: 0,
                weekNumber: 0,
                exercisePerformances: [perf],
                notes: notes
            )

            context.insert(workout)
            workoutCount += 1
            setCount += sets.count
        }

        return ImportResult(
            workoutsImported: workoutCount,
            setsImported: setCount,
            exercisesFound: allExercises,
            unmappedExercises: unmapped,
            errors: parseErrors
        )
    }

    // MARK: - Accessory Import

    /// Import accessory exercises found in the Strong CSV into the exercise library
    static func importAccessoryExercises(_ csvString: String, context: ModelContext) -> [String] {
        let (rows, _) = parseCSV(csvString)
        var added: [String] = []

        let allNames = Set(rows.map(\.exerciseName))

        for name in allNames {
            // Skip if it's a main lift
            if Lift.fromStrongName(name) != nil { continue }

            // Check if already in library
            let predicate = #Predicate<Exercise> { $0.name == name }
            let descriptor = FetchDescriptor<Exercise>(predicate: predicate)
            let existing = (try? context.fetchCount(descriptor)) ?? 0
            guard existing == 0 else { continue }

            // Add with best-guess category
            let category = guessCategory(for: name)
            context.insert(Exercise(name: name, category: category, equipmentType: guessEquipment(for: name), isCustom: false))
            added.append(name)
        }

        return added
    }

    private static func guessCategory(for name: String) -> ExerciseCategory {
        let lower = name.lowercased()
        if lower.contains("curl") || lower.contains("row") || lower.contains("pull") ||
           lower.contains("lat") || lower.contains("chin") || lower.contains("face") ||
           lower.contains("rear delt") || lower.contains("shrug") {
            return .pull
        }
        if lower.contains("lunge") || lower.contains("split") || lower.contains("leg") ||
           lower.contains("calf") || lower.contains("ab") || lower.contains("plank") ||
           lower.contains("crunch") || lower.contains("hip") || lower.contains("glute") ||
           lower.contains("romanian") || lower.contains("extension") {
            return .singleLegCore
        }
        return .push
    }

    private static func guessEquipment(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("barbell") { return "barbell" }
        if lower.contains("dumbbell") { return "dumbbell" }
        if lower.contains("cable") { return "cable" }
        if lower.contains("machine") { return "machine" }
        if lower.contains("bodyweight") || lower.contains("push-up") || lower.contains("pull-up") || lower.contains("dip") {
            return "bodyweight"
        }
        return "other"
    }
}
