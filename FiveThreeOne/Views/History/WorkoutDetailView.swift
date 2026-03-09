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
                    HStack(spacing: 12) {
                        if workout.durationSeconds > 0 {
                            Label(workout.formattedDuration, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if let hr = workout.averageHeartRate {
                            Label("\(Int(hr)) avg BPM", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        if let cal = workout.estimatedCalories {
                            Label("\(Int(cal)) kcal", systemImage: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange.opacity(0.7))
                        }
                        if workout.totalVolume > 0 {
                            Label("\(workout.formattedVolume) lbs", systemImage: "scalemass.fill")
                                .font(.caption)
                                .foregroundStyle(.blue.opacity(0.7))
                        }
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

            if perf.totalVolume > 0 {
                HStack(spacing: 12) {
                    Text("\(perf.completedWorkingSets) sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(perf.totalReps) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(perf.totalVolume)) lbs vol")
                        .font(.caption)
                        .foregroundStyle(.blue)
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
                        if let hr = set.averageHR {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.6))
                            Text("\(Int(hr))")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.6))
                                .monospacedDigit()
                        }
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
