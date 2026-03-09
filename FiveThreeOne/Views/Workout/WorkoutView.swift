import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    let cycle: Cycle
    let lift: Lift
    let week: Int

    @State private var completedSets: [CompletedSet] = []
    @State private var supplementalCompletedSets: [CompletedSet] = []
    @State private var showingRestTimer = false
    @State private var workoutStartTime: Date?
    @State private var notes = ""

    private var userSettings: UserSettings? { settings.first }
    private var roundTo: Double { userSettings?.roundTo ?? 5.0 }
    private var barWeight: Double { userSettings?.barWeight ?? 45.0 }
    private var plates: [Double] { userSettings?.availablePlates ?? [45, 35, 25, 10, 5, 2.5] }

    private var plannedMain: [ProgramEngine.PlannedSet] {
        ProgramEngine.mainSets(
            trainingMax: cycle.trainingMax(for: lift),
            week: week,
            variant: cycle.programVariant,
            roundTo: roundTo
        )
    }

    private var plannedSupplemental: [ProgramEngine.PlannedSet] {
        ProgramEngine.supplementalSets(
            trainingMax: cycle.trainingMax(for: lift),
            week: week,
            variant: cycle.programVariant,
            roundTo: roundTo
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                mainSetsSection
                if !plannedSupplemental.isEmpty {
                    supplementalSetsSection
                }
                notesSection
                finishButton
            }
            .padding()
        }
        .navigationTitle(lift.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if workoutStartTime == nil {
                workoutStartTime = .now
                initializeSets()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Cycle \(cycle.number) — Week \(week)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(ProgramEngine.weekLabel(week))
                .font(.title2)
                .fontWeight(.bold)
            Text(cycle.programVariant.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Main Sets

    private var mainSetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Main Sets")
                .font(.headline)

            ForEach(Array(plannedMain.enumerated()), id: \.element.id) { index, planned in
                SetRowView(
                    planned: planned,
                    completed: $completedSets[index],
                    barWeight: barWeight,
                    availablePlates: plates
                )
            }
        }
    }

    // MARK: - Supplemental Sets

    private var supplementalSetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supplemental (\(cycle.programVariant.displayName))")
                .font(.headline)

            ForEach(Array(plannedSupplemental.enumerated()), id: \.element.id) { index, planned in
                SetRowView(
                    planned: planned,
                    completed: $supplementalCompletedSets[index],
                    barWeight: barWeight,
                    availablePlates: plates
                )
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.headline)
            TextField("Workout notes...", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }

    private var finishButton: some View {
        Button {
            saveWorkout()
        } label: {
            Text("Finish Workout")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!allMainSetsComplete)
    }

    private var allMainSetsComplete: Bool {
        completedSets.allSatisfy { $0.isComplete }
    }

    // MARK: - Actions

    private func initializeSets() {
        completedSets = plannedMain.map { planned in
            CompletedSet(
                weight: planned.weight,
                targetReps: planned.reps,
                actualReps: 0,
                isAMRAP: planned.isAMRAP,
                setType: planned.setType
            )
        }
        supplementalCompletedSets = plannedSupplemental.map { planned in
            CompletedSet(
                weight: planned.weight,
                targetReps: planned.reps,
                actualReps: 0,
                isAMRAP: false,
                setType: planned.setType
            )
        }
    }

    private func saveWorkout() {
        let duration = Int(Date.now.timeIntervalSince(workoutStartTime ?? .now))
        let workout = CompletedWorkout(
            date: .now,
            lift: lift,
            cycleNumber: cycle.number,
            weekNumber: week,
            sets: completedSets,
            accessorySets: supplementalCompletedSets,
            notes: notes,
            durationSeconds: duration,
            variant: cycle.programVariant
        )
        modelContext.insert(workout)
        dismiss()
    }
}
