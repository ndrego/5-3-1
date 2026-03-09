import SwiftUI

struct WorkoutDetailView: View {
    let workout: CompletedWorkout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.date, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if workout.cycleNumber > 0 {
                        Text("Cycle \(workout.cycleNumber) — Week \(workout.weekNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if workout.durationSeconds > 0 {
                        Text(workout.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Main Sets
                if !workout.sets.isEmpty {
                    setsSection(title: "Main Sets", sets: workout.sets)
                }

                // Supplemental / Accessory Sets
                if !workout.accessorySets.isEmpty {
                    setsSection(title: "Supplemental", sets: workout.accessorySets)
                }

                // Estimated 1RM from AMRAP
                if let topSet = workout.sets.first(where: { $0.isAMRAP }),
                   topSet.actualReps > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated 1RM")
                            .font(.headline)
                        let e1rm = ProgramEngine.estimated1RM(weight: topSet.weight, reps: topSet.actualReps)
                        Text("\(Int(e1rm)) lbs")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Epley formula: \(Int(topSet.weight)) × \(topSet.actualReps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Notes
                if !workout.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.headline)
                        Text(workout.notes)
                            .font(.body)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(workout.liftType.displayName)
    }

    @ViewBuilder
    private func setsSection(title: String, sets: [CompletedSet]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text("Set \(index + 1)")
                        .font(.subheadline)
                        .frame(width: 50, alignment: .leading)

                    Text("\(Int(set.weight)) lbs")
                        .monospacedDigit()

                    Spacer()

                    HStack(spacing: 4) {
                        Text("\(set.actualReps)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        if set.isAMRAP {
                            Text("/ \(set.targetReps)+")
                                .foregroundStyle(.secondary)
                            if set.exceededTarget {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        } else {
                            Text("/ \(set.targetReps)")
                                .foregroundStyle(.secondary)
                        }
                        Text("reps")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
