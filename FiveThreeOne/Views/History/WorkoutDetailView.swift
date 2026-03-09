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

                // Exercise performances
                ForEach(workout.allExercisePerformances.sorted(by: { $0.sortOrder < $1.sortOrder })) { perf in
                    exerciseSection(perf)
                }

                // Estimated 1RM from AMRAP sets
                ForEach(workout.allExercisePerformances.filter { $0.isMainLift }) { perf in
                    if let topSet = perf.sets.first(where: { $0.isAMRAP }), topSet.actualReps > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(perf.exerciseName) — Estimated 1RM")
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
        .navigationTitle(workout.displayName)
    }

    @ViewBuilder
    private func exerciseSection(_ perf: ExercisePerformance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(perf.exerciseName)
                    .font(.headline)
                if perf.isMainLift {
                    Text("5/3/1")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            ForEach(Array(perf.sets.enumerated()), id: \.element.id) { index, set in
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
                        } else if set.targetReps > 0 {
                            Text("/ \(set.targetReps)")
                                .foregroundStyle(.secondary)
                        }
                        Text("reps")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
