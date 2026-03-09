import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Query(sort: \CompletedWorkout.date, order: .reverse) private var workouts: [CompletedWorkout]

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "clock",
                        description: Text("Complete a workout to see it here, or import from Strong.")
                    )
                } else {
                    List {
                        ForEach(groupedByMonth, id: \.key) { month, monthWorkouts in
                            Section(month) {
                                ForEach(monthWorkouts) { workout in
                                    NavigationLink {
                                        WorkoutDetailView(workout: workout)
                                    } label: {
                                        WorkoutRowView(workout: workout)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private var groupedByMonth: [(key: String, value: [CompletedWorkout])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: workouts) { workout in
            formatter.string(from: workout.date)
        }

        return grouped.sorted { a, b in
            guard let dateA = a.value.first?.date, let dateB = b.value.first?.date else { return false }
            return dateA > dateB
        }
    }
}

struct WorkoutRowView: View {
    let workout: CompletedWorkout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if workout.cycleNumber > 0 {
                        Text("C\(workout.cycleNumber) W\(workout.weekNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(workout.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if workout.durationSeconds > 0 {
                        Text(workout.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if workout.totalVolume > 0 {
                        Text("\(workout.formattedVolume) lbs")
                            .font(.caption)
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                }
            }

            Spacer()

            if let topReps = workout.topSetReps, let topWeight = workout.topSetWeight {
                VStack(alignment: .trailing) {
                    Text("\(Int(topWeight))×\(topReps)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("Top Set")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
