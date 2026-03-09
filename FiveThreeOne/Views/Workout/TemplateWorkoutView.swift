import SwiftUI
import SwiftData

struct TemplateWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    let template: WorkoutTemplate
    let cycle: Cycle?
    let week: Int

    @State private var exerciseStates: [ExerciseState] = []
    @State private var workoutStartTime: Date?
    @State private var notes = ""
    @State private var restTimer = RestTimerState()
    @State private var initialized = false

    private var userSettings: UserSettings? { settings.first }
    private var roundTo: Double { userSettings?.roundTo ?? 5.0 }
    private var barWeight: Double { userSettings?.barWeight ?? 45.0 }
    private var plates: [Double] { userSettings?.availablePlates ?? [45, 35, 25, 10, 5, 2.5] }

    var body: some View {
        List {
            // Header
            Section {
                header
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            // Rest timer
            if restTimer.isRunning {
                Section {
                    RestTimerView(timer: restTimer)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Exercise sections
            ForEach($exerciseStates) { $exerciseState in
                exerciseSection(for: $exerciseState)
            }

            // Notes
            Section("Notes") {
                TextField("Workout notes...", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Finish
            Section {
                Button {
                    saveWorkout()
                } label: {
                    Text("Finish Workout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            workoutStartTime = .now
            initializeExercises()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            if let cycle {
                Text("Cycle \(cycle.number) — Week \(week)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(ProgramEngine.weekLabel(week))
                    .font(.title2)
                    .fontWeight(.bold)
                Text(cycle.programVariant.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Week \(week)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(for exerciseState: Binding<ExerciseState>) -> some View {
        let state = exerciseState.wrappedValue
        return Section {
            if state.isMainLift {
                mainLiftRows(for: exerciseState)
            } else {
                accessoryRows(for: exerciseState)
            }
        } header: {
            HStack {
                Text(state.exerciseName)
                if state.isMainLift {
                    Text("5/3/1")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Spacer()
                if let previousSummary = state.previousBestSummary {
                    Text("Prev: \(previousSummary)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Main Lift Rows

    @ViewBuilder
    private func mainLiftRows(for exerciseState: Binding<ExerciseState>) -> some View {
        let state = exerciseState.wrappedValue
        ForEach(Array(state.sets.indices), id: \.self) { index in
            mainSetRow(for: exerciseState.sets[index], setIndex: index, state: state)
        }
    }

    private func mainSetRow(for set: Binding<CompletedSet>, setIndex: Int, state: ExerciseState) -> some View {
        let planned = setIndex < state.plannedSets.count ? state.plannedSets[setIndex] : nil
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Weight", value: set.weight, format: .number)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .frame(width: 70)
                        .padding(4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("lbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if set.wrappedValue.isAMRAP {
                        Text("AMRAP")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                if let p = planned {
                    Text("\(Int(p.percentage * 100))% × \(p.reps)\(p.isAMRAP ? "+" : "") — \(p.setType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Plate info
            if planned != nil {
                Text(PlateCalculator.calculate(
                    totalWeight: set.wrappedValue.weight,
                    barWeight: barWeight,
                    availablePlates: plates
                ).description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Rep input
            mainRepInput(for: set)
        }
        .listRowBackground(set.wrappedValue.isComplete ? Color.green.opacity(0.08) : nil)
    }

    @ViewBuilder
    private func mainRepInput(for set: Binding<CompletedSet>) -> some View {
        if set.wrappedValue.isAMRAP {
            HStack(spacing: 8) {
                Button {
                    if set.wrappedValue.actualReps > 0 {
                        set.wrappedValue.actualReps -= 1
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }

                Text("\(set.wrappedValue.actualReps)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .frame(minWidth: 36)

                Button {
                    set.wrappedValue.actualReps += 1
                    startRestIfNeeded(setType: .main)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        } else {
            Button {
                let wasComplete = set.wrappedValue.isComplete
                set.wrappedValue.actualReps = wasComplete ? 0 : set.wrappedValue.targetReps
                if !wasComplete {
                    startRestIfNeeded(setType: set.wrappedValue.setType)
                }
            } label: {
                Image(systemName: set.wrappedValue.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(set.wrappedValue.isComplete ? .green : .secondary)
            }
            .frame(width: 44, height: 44)
        }
    }

    // MARK: - Accessory Rows

    @ViewBuilder
    private func accessoryRows(for exerciseState: Binding<ExerciseState>) -> some View {
        let state = exerciseState.wrappedValue
        ForEach(Array(state.sets.indices), id: \.self) { index in
            accessorySetRow(
                setNumber: index + 1,
                set: exerciseState.sets[index],
                previousSet: index < state.previousSets.count ? state.previousSets[index] : nil
            )
            .onChange(of: exerciseState.sets[index].wrappedValue.actualReps) { oldVal, newVal in
                if oldVal == 0 && newVal > 0 {
                    startRestIfNeeded(setType: .accessory)
                }
            }
        }

        Button {
            let prevSet = state.previousSets.count > state.sets.count
                ? state.previousSets[state.sets.count]
                : state.sets.last
            let newSet = CompletedSet(
                weight: prevSet?.weight ?? 0,
                targetReps: prevSet?.actualReps ?? 10,
                setType: .accessory
            )
            exerciseState.wrappedValue.sets.append(newSet)
        } label: {
            Label("Add Set", systemImage: "plus.circle")
                .font(.subheadline)
        }
    }

    private func accessorySetRow(setNumber: Int, set: Binding<CompletedSet>, previousSet: CompletedSet?) -> some View {
        HStack(spacing: 12) {
            Text("\(setNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Weight — pre-filled from previous, editable
            TextField("0", value: set.weight, format: .number)
                .font(.body)
                .fontWeight(.medium)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .frame(width: 60)
                .padding(4)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("lbs")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Reps — binds to targetReps (pre-filled from previous), user edits before confirming
            TextField("0", value: set.targetReps, format: .number)
                .font(.body)
                .fontWeight(.medium)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .frame(width: 40)
                .padding(4)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("reps")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            // Tap to confirm: copies targetReps → actualReps
            Button {
                if set.wrappedValue.isComplete {
                    set.wrappedValue.actualReps = 0
                } else {
                    set.wrappedValue.actualReps = set.wrappedValue.targetReps
                }
            } label: {
                Image(systemName: set.wrappedValue.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.wrappedValue.isComplete ? .green : .secondary)
            }
            .frame(width: 44, height: 44)
        }
        .listRowBackground(set.wrappedValue.isComplete ? Color.green.opacity(0.08) : nil)
    }

    // MARK: - Rest Timer

    private func startRestIfNeeded(setType: SetType) {
        guard let settings = userSettings else { return }
        let seconds: Int
        switch setType {
        case .main:
            seconds = settings.defaultRestSeconds
        case .supplemental:
            seconds = settings.supplementalRestSeconds
        case .accessory:
            seconds = settings.accessoryRestSeconds
        case .joker:
            seconds = settings.defaultRestSeconds
        }
        restTimer.start(seconds: seconds)
    }

    // MARK: - Initialize

    private func initializeExercises() {
        exerciseStates = template.exerciseEntries
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { entry in
                let previous = PreviousPerformanceLookup.lastPerformance(
                    exerciseName: entry.exerciseName,
                    in: modelContext
                )

                var state = ExerciseState(
                    id: entry.id,
                    exerciseName: entry.exerciseName,
                    mainLift: entry.mainLift,
                    sets: [],
                    plannedSets: [],
                    previousSets: previous?.sets ?? [],
                    previousBestSummary: previous?.bestSetSummary
                )

                if let lift = entry.lift, let cycle {
                    let tm = cycle.trainingMax(for: lift)
                    let mainPlanned = ProgramEngine.mainSets(
                        trainingMax: tm, week: week,
                        variant: cycle.programVariant, roundTo: roundTo
                    )
                    let suppPlanned = ProgramEngine.supplementalSets(
                        trainingMax: tm, week: week,
                        variant: cycle.programVariant, roundTo: roundTo
                    )
                    let allPlanned = mainPlanned + suppPlanned
                    state.plannedSets = allPlanned
                    state.sets = allPlanned.map { planned in
                        CompletedSet(
                            weight: planned.weight,
                            targetReps: planned.reps,
                            actualReps: 0,
                            isAMRAP: planned.isAMRAP,
                            setType: planned.setType
                        )
                    }
                } else {
                    let setCount = max(previous?.sets.count ?? 3, 3)
                    state.sets = (0..<setCount).map { i in
                        let prev = i < (previous?.sets.count ?? 0) ? previous?.sets[i] : nil
                        return CompletedSet(
                            weight: prev?.weight ?? 0,
                            targetReps: prev?.actualReps ?? 10,
                            setType: .accessory
                        )
                    }
                }

                return state
            }
    }

    // MARK: - Save

    private func saveWorkout() {
        let duration = Int(Date.now.timeIntervalSince(workoutStartTime ?? .now))

        let performances = exerciseStates.enumerated().map { index, state in
            ExercisePerformance(
                exerciseName: state.exerciseName,
                mainLift: state.mainLift,
                sets: state.sets,
                sortOrder: index
            )
        }

        let workout = CompletedWorkout(
            date: .now,
            templateName: template.name,
            cycleNumber: cycle?.number ?? 0,
            weekNumber: week,
            exercisePerformances: performances,
            notes: notes,
            durationSeconds: duration,
            variant: cycle?.programVariant ?? .standard
        )
        modelContext.insert(workout)
        restTimer.stop()
        dismiss()
    }
}

// MARK: - Exercise State

struct ExerciseState: Identifiable {
    let id: UUID
    var exerciseName: String
    var mainLift: String?
    var sets: [CompletedSet]
    var plannedSets: [ProgramEngine.PlannedSet]
    var previousSets: [CompletedSet]
    var previousBestSummary: String?

    var isMainLift: Bool { mainLift != nil }
    var lift: Lift? { mainLift.flatMap { Lift(rawValue: $0) } }
}
