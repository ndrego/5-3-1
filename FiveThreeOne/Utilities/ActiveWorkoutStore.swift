import Foundation

/// Persists active workout state to disk for crash recovery.
/// Saves a lightweight JSON snapshot that can rebuild the workout view.
enum ActiveWorkoutStore {
    private static let fileName = "ActiveWorkout.json"

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// Save current workout state to disk.
    static func save(_ snapshot: WorkoutSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ActiveWorkoutStore] Save failed: \(error.localizedDescription)")
        }
    }

    /// Load a previously saved workout snapshot, if any.
    static func load() -> WorkoutSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(WorkoutSnapshot.self, from: data)
        } catch {
            print("[ActiveWorkoutStore] Load failed: \(error.localizedDescription)")
            delete()
            return nil
        }
    }

    /// Delete the recovery file (called after successful save or discard).
    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Whether a recovery file exists.
    static var hasRecoveryData: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}

// MARK: - Snapshot Model

struct WorkoutSnapshot: Codable {
    let templateName: String
    let cycleNumber: Int
    let weekNumber: Int
    let variant: String
    let workoutStartTime: Date
    let notes: String
    let exercises: [ExerciseSnapshot]
    let savedAt: Date

    struct ExerciseSnapshot: Codable {
        let id: String  // UUID string
        let exerciseName: String
        let mainLift: String?
        let sets: [CompletedSet]
        let supersetGroup: Int?
        let isUnilateral: Bool
        let equipmentType: String
        let isTimed: Bool
        let supersetSubGroup: Int?
    }
}
