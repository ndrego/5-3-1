import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var workout: CompletedWorkout
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                ForEach(workout.allExercisePerformances.sorted(by: { $0.sortOrder < $1.sortOrder })) { perf in
                    exerciseSection(perf)
                }

                // Estimated 1RM from AMRAP sets
                if !isEditing {
                    ForEach(workout.allExercisePerformances.filter { $0.isMainLift }) { perf in
                        if let topSet = perf.sets.first(where: { $0.isAMRAP }), topSet.actualReps > 0 {
                            estimated1RMCard(perf: perf, topSet: topSet)
                        }
                    }
                }

                notesSection
            }
            .padding()
        }
        .navigationTitle(workout.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation { isEditing.toggle() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
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
    }

    // MARK: - Exercise Section

    @ViewBuilder
    private func exerciseSection(_ perf: ExercisePerformance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                ExerciseDetailView(exerciseName: perf.exerciseName)
            } label: {
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
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exercise-link-\(perf.exerciseName)")

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
                if isEditing {
                    editableSetRow(perfId: perf.id, index: index, set: set)
                } else {
                    readOnlySetRow(index: index, set: set)
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Set Rows

    private func readOnlySetRow(index: Int, set: CompletedSet) -> some View {
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
                    if let rpe = set.estimatedRPE {
                        Text("RPE \(String(format: "%.0f", rpe))")
                            .font(.caption2)
                            .foregroundStyle(rpeColor(rpe))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func editableSetRow(perfId: UUID, index: Int, set: CompletedSet) -> some View {
        HStack {
            Text("Set \(index + 1)")
                .font(.subheadline)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { set.weight },
                    set: { newWeight in updateSet(perfId: perfId, setId: set.id) { $0.weight = newWeight } }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 55)
                .textFieldStyle(.roundedBorder)
                Text("lbs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { set.actualReps },
                    set: { newReps in updateSet(perfId: perfId, setId: set.id) { $0.actualReps = newReps } }
                ), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .textFieldStyle(.roundedBorder)
                Text("reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.headline)
                TextField("Workout notes...", text: $workout.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
        } else if !workout.notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.headline)
                Text(workout.notes)
                    .font(.body)
            }
        }
    }

    // MARK: - 1RM Card

    private func estimated1RMCard(perf: ExercisePerformance, topSet: CompletedSet) -> some View {
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

    // MARK: - Helpers

    private func updateSet(perfId: UUID, setId: UUID, transform: (inout CompletedSet) -> Void) {
        guard let perfIndex = workout.exercisePerformances.firstIndex(where: { $0.id == perfId }),
              let setIndex = workout.exercisePerformances[perfIndex].sets.firstIndex(where: { $0.id == setId }) else { return }
        transform(&workout.exercisePerformances[perfIndex].sets[setIndex])
    }

    private func rpeColor(_ rpe: Double) -> Color {
        switch rpe {
        case ..<7: return .green
        case ..<8: return .yellow
        case ..<9: return .orange
        default: return .red
        }
    }
}
