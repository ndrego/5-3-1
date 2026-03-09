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

            // Skip rest timer rows (Strong exports these between sets)
            if fields[4].lowercased().contains("rest") { continue }

            guard let date = parseDate(fields[0]) else {
                errors.append("Line \(lineIndex + 2): invalid date '\(fields[0])'")
                continue
            }

            let row = StrongRow(
                date: date,
                workoutName: fields[1],
                duration: fields[2],
                exerciseName: fields[3],
                setOrder: Int(fields[4]) ?? Int(Double(fields[4]) ?? 1),
                weight: Double(fields[5]) ?? 0,
                reps: Int(fields[6]) ?? Int(Double(fields[6]) ?? 0),
                distance: fields.count > 7 ? Double(fields[7]) ?? 0 : 0,
                seconds: fields.count > 8 ? (Int(fields[8]) ?? Int(Double(fields[8]) ?? 0)) : 0,
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

    /// Parse Strong duration string like "1h 23m", "45m 30s", "1h 23m 45s"
    private static func parseDuration(_ string: String) -> Int {
        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)
        var totalSeconds = 0

        // Match hours
        if let hRange = lower.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            let numStr = lower[hRange].filter(\.isNumber)
            totalSeconds += (Int(numStr) ?? 0) * 3600
        }
        // Match minutes
        if let mRange = lower.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            let numStr = lower[mRange].filter(\.isNumber)
            totalSeconds += (Int(numStr) ?? 0) * 60
        }
        // Match seconds
        if let sRange = lower.range(of: #"(\d+)\s*s"#, options: .regularExpression) {
            let numStr = lower[sRange].filter(\.isNumber)
            totalSeconds += Int(numStr) ?? 0
        }

        return totalSeconds
    }

    /// Known unilateral exercise patterns
    private static func isLikelyUnilateral(_ name: String) -> Bool {
        let lower = name.lowercased()
        let patterns = [
            "single arm", "single leg", "single-arm", "single-leg",
            "one arm", "one leg", "one-arm", "one-leg",
            "unilateral", "bulgarian", "lunge", "split squat",
            "dumbbell curl", "hammer curl", "dumbbell row",
            "side plank", "side bend", "pistol squat",
            "concentration curl"
        ]
        return patterns.contains(where: { lower.contains($0) })
    }

    // MARK: - Import

    /// Normalize a Strong exercise name to match our exercise library.
    /// e.g. "Romanian Deadlift (Barbell)" → "Romanian Deadlift" if that exists in our library.
    private static func normalizeExerciseName(_ strongName: String, knownNames: Set<String>) -> String {
        // Direct match
        if knownNames.contains(strongName) { return strongName }

        // Try stripping parenthetical equipment suffix: "Exercise (Barbell)" → "Exercise"
        if let parenRange = strongName.range(of: #"\s*\([^)]+\)\s*$"#, options: .regularExpression) {
            let stripped = String(strongName[strongName.startIndex..<parenRange.lowerBound])
            if knownNames.contains(stripped) { return stripped }
        }

        return strongName
    }

    /// Import Strong CSV data into the app's data store.
    /// Groups all exercises from the same session into a single CompletedWorkout.
    /// Imports both main lifts and accessory exercises as workout history.
    static func importCSV(_ csvString: String, context: ModelContext) -> ImportResult {
        let (rows, parseErrors) = parseCSV(csvString)

        // Clear previously imported workouts (cycle 0 = imported data)
        let importedPredicate = #Predicate<CompletedWorkout> { $0.cycleNumber == 0 }
        let importedDescriptor = FetchDescriptor<CompletedWorkout>(predicate: importedPredicate)
        if let existing = try? context.fetch(importedDescriptor) {
            for workout in existing {
                context.delete(workout)
            }
        }

        // Build set of known exercise names from our library for name normalization
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let knownExercises = (try? context.fetch(exerciseDescriptor)) ?? []
        let knownNames = Set(knownExercises.map(\.name))

        var allExercises: Set<String> = []
        var unmapped: Set<String> = []
        var workoutCount = 0
        var setCount = 0

        // Group rows by session: same date = same workout session
        // Strong uses the exact same timestamp for all rows in a session
        var sessionGroups: [Date: [StrongRow]] = [:]
        for row in rows {
            allExercises.insert(row.exerciseName)
            sessionGroups[row.date, default: []].append(row)
        }

        // Process each session
        for (sessionDate, sessionRows) in sessionGroups.sorted(by: { $0.key < $1.key }) {
            // Group by exercise within the session
            var exerciseGroups: [(name: String, rows: [StrongRow])] = []
            var seen: [String: Int] = [:]

            for row in sessionRows.sorted(by: { $0.setOrder < $1.setOrder }) {
                if let idx = seen[row.exerciseName] {
                    exerciseGroups[idx].rows.append(row)
                } else {
                    seen[row.exerciseName] = exerciseGroups.count
                    exerciseGroups.append((name: row.exerciseName, rows: [row]))
                }
            }

            // Build ExercisePerformance for each exercise
            var performances: [ExercisePerformance] = []
            var hasMainLift = false
            var mainLiftName = ""

            for (sortOrder, group) in exerciseGroups.enumerated() {
                let lift = Lift.fromStrongName(group.name)
                let isUnilateral = isLikelyUnilateral(group.name)

                if lift != nil {
                    hasMainLift = true
                    mainLiftName = lift!.displayName
                } else {
                    unmapped.insert(group.name)
                }

                let sets = group.rows.map { row in
                    CompletedSet(
                        weight: row.weight,
                        targetReps: row.reps,
                        actualReps: row.reps,
                        isAMRAP: false,
                        setType: lift != nil ? .main : .accessory
                    )
                }

                let displayName = lift?.displayName ?? normalizeExerciseName(group.name, knownNames: knownNames)

                let perf = ExercisePerformance(
                    exerciseName: displayName,
                    mainLift: lift?.rawValue,
                    sets: sets,
                    sortOrder: sortOrder,
                    isUnilateral: isUnilateral
                )
                performances.append(perf)
                setCount += sets.count
            }

            // Determine workout name
            let templateName: String
            if hasMainLift {
                templateName = mainLiftName
            } else {
                let workoutName = sessionRows.first?.workoutName ?? ""
                templateName = workoutName.isEmpty ? "Workout" : workoutName
            }

            // Parse duration from first row
            let durationSeconds = parseDuration(sessionRows.first?.duration ?? "")

            let notes = sessionRows.first(where: { !$0.workoutNotes.isEmpty })?.workoutNotes ?? ""

            let workout = CompletedWorkout(
                date: sessionDate,
                templateName: templateName,
                cycleNumber: 0,
                weekNumber: 0,
                exercisePerformances: performances,
                notes: notes,
                durationSeconds: durationSeconds
            )

            context.insert(workout)
            workoutCount += 1
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

        // Build known names for normalization
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let knownExercises = (try? context.fetch(exerciseDescriptor)) ?? []
        let knownNames = Set(knownExercises.map(\.name))

        let allNames = Set(rows.map(\.exerciseName))

        for name in allNames {
            // Skip if it's a main lift
            if Lift.fromStrongName(name) != nil { continue }

            // Normalize name to match existing library entries
            let normalized = normalizeExerciseName(name, knownNames: knownNames)

            // Skip if already in library (check both original and normalized)
            let checkName = normalized
            let predicate = #Predicate<Exercise> { $0.name == checkName }
            let descriptor = FetchDescriptor<Exercise>(predicate: predicate)
            let existing = (try? context.fetchCount(descriptor)) ?? 0
            guard existing == 0 else { continue }

            // Add with best-guess category
            let category = guessCategory(for: name)
            let unilateral = isLikelyUnilateral(name)
            context.insert(Exercise(name: normalized, category: category, equipmentType: guessEquipment(for: name), isCustom: false, isUnilateral: unilateral))
            added.append(normalized)
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
