import SwiftUI
import SwiftData
import UIKit

struct TemplateWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    let template: WorkoutTemplate
    let cycle: Cycle?
    let week: Int

    @State private var exerciseStates: [ExerciseState] = []
    @State private var workoutStartTime: Date?
    @State private var workoutStarted = false
    @State private var notes = ""
    @State private var restTimer = RestTimerState()
    @State private var initialized = false
    @State private var isReordering = false
    @State private var showingSaveTemplateSheet = false
    @State private var templateChanges = TemplateChanges()
    @State private var showingSupersetPicker = false
    @State private var supersetSourceIndex: Int?
    @State private var heartRateManager = HeartRateManager()
    @State private var phoneConnectivity = PhoneConnectivityManager()
    @State private var showPlatesForSet: Set<UUID> = []

    private var userSettings: UserSettings? { settings.first }
    private var roundTo: Double { userSettings?.roundTo ?? 5.0 }
    private var barWeight: Double { userSettings?.barWeight ?? 45.0 }
    private var plates: [Double] { userSettings?.availablePlates ?? [45, 35, 25, 10, 5, 2.5] }

    var body: some View {
        List {
            if isReordering {
                // Reorder mode: compact rows with drag handles
                Section("Drag to Reorder") {
                    ForEach($exerciseStates) { $state in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(state.exerciseName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                if state.isMainLift {
                                    Text("5/3/1")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                        }
                    }
                    .onMove { from, to in
                        exerciseStates.move(fromOffsets: from, toOffset: to)
                    }
                }
            } else {
                // Header
                Section {
                    header
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                // Start button (before workout begins)
                if !workoutStarted {
                    Section {
                        Button {
                            workoutStartTime = .now
                            workoutStarted = true
                            UIApplication.shared.isIdleTimerDisabled = true
                            phoneConnectivity.sendWorkoutStarted()
                            phoneConnectivity.sendRepCountingEnabled(userSettings?.repCountingEnabled ?? false)
                            sendWatchContext()
                        } label: {
                            Label("Start Workout", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .listRowBackground(Color.clear)
                    }
                }

                // Exercise sections (grouped by superset)
                ForEach(exerciseSectionGroups, id: \.id) { group in
                    if group.indices.count > 1 {
                        supersetSection(for: group)
                    } else if let idx = group.indices.first {
                        exerciseSection(for: $exerciseStates[idx], index: idx)
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Workout notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Finish
                if workoutStarted {
                    Section {
                        Button {
                            saveWorkout()
                        } label: {
                            Label("Finish Workout", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if workoutStarted {
                WorkoutBottomBar(
                    restTimer: restTimer,
                    heartRateManager: heartRateManager,
                    workoutStartTime: $workoutStartTime
                )
            }
        }
        .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isReordering ? "Done" : "Reorder") {
                    withAnimation {
                        isReordering.toggle()
                    }
                }
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            initializeExercises()
            phoneConnectivity.activate()
        }
        .task {
            if heartRateManager.isAvailable {
                await heartRateManager.requestAuthorization()
            }
            #if DEBUG && targetEnvironment(simulator)
            heartRateManager.isSimulating = true
            heartRateManager.startMonitoring()
            #else
            if heartRateManager.isAuthorized {
                heartRateManager.startMonitoring()
            }
            #endif
        }
        .onChange(of: restTimer.isRunning) { _, isRunning in
            if !isRunning {
                phoneConnectivity.sendTimerStopped()
            }
        }
        .onChange(of: phoneConnectivity.watchRequestedStopTimer) {
            guard phoneConnectivity.watchRequestedStopTimer else { return }
            phoneConnectivity.watchRequestedStopTimer = false
            restTimer.stop()
        }
        .onChange(of: phoneConnectivity.watchRequestedCompleteSet) {
            guard phoneConnectivity.watchRequestedCompleteSet else { return }
            phoneConnectivity.watchRequestedCompleteSet = false
            completeNextSet()
        }
        .onChange(of: phoneConnectivity.watchReportedRepCount) {
            guard let count = phoneConnectivity.watchReportedRepCount else { return }
            phoneConnectivity.watchReportedRepCount = nil
            updateCurrentSetReps(count)
        }
        .onDisappear {
            heartRateManager.stopMonitoring()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showingSupersetPicker) {
            supersetPickerSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSaveTemplateSheet) {
            SaveTemplateChangesView(
                changes: templateChanges,
                onSave: { selections in
                    applyTemplateChanges(selections)
                    dismiss()
                },
                onSkip: {
                    dismiss()
                }
            )
            .presentationDetents([.medium])
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

    // MARK: - Section Grouping

    /// Groups exercises into superset groups or standalone entries.
    private var exerciseSectionGroups: [ExerciseSectionGroup] {
        var groups: [ExerciseSectionGroup] = []
        var usedIndices = Set<Int>()

        for (index, state) in exerciseStates.enumerated() {
            guard !usedIndices.contains(index) else { continue }

            if let group = state.supersetGroup {
                // Collect all exercises in this superset group
                let indices = exerciseStates.indices.filter {
                    exerciseStates[$0].supersetGroup == group && !usedIndices.contains($0)
                }
                for i in indices { usedIndices.insert(i) }
                groups.append(ExerciseSectionGroup(indices: indices, supersetGroup: group))
            } else {
                usedIndices.insert(index)
                groups.append(ExerciseSectionGroup(indices: [index], supersetGroup: nil))
            }
        }
        return groups
    }

    private var nextSupersetGroupNumber: Int {
        let existing = exerciseStates.compactMap { $0.supersetGroup }
        return (existing.max() ?? 0) + 1
    }

    // MARK: - Exercise Section (standalone)

    private func exerciseSection(for exerciseState: Binding<ExerciseState>, index: Int) -> some View {
        let state = exerciseState.wrappedValue
        return Section {
            if state.isMainLift {
                mainLiftRows(for: exerciseState)
            } else {
                accessoryRows(for: exerciseState)
            }

            // Superset link button
            Button {
                supersetSourceIndex = index
                showingSupersetPicker = true
            } label: {
                Label("Superset with...", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        } header: {
            exerciseSectionHeader(for: $exerciseStates[index])
        }
    }

    // MARK: - Superset Section (interleaved)

    @ViewBuilder
    private func supersetSection(for group: ExerciseSectionGroup) -> some View {
        let states = group.indices.map { exerciseStates[$0] }
        let names = states.map { $0.exerciseName }.joined(separator: " + ")
        let maxSets = states.map { $0.sets.count }.max() ?? 0

        Section {
            ForEach(0..<maxSets, id: \.self) { setIndex in
                ForEach(Array(group.indices.enumerated()), id: \.offset) { offset, exerciseIdx in
                    let state = exerciseStates[exerciseIdx]
                    if setIndex < state.sets.count {
                        supersetRow(
                            exerciseIndex: exerciseIdx,
                            setIndex: setIndex,
                            label: supersetLabel(offset: offset),
                            state: state,
                            isLastInRound: offset == group.indices.count - 1
                        )
                    }
                }
            }

            // Unlink button
            Button {
                for idx in group.indices {
                    exerciseStates[idx].supersetGroup = nil
                }
            } label: {
                Label("Unlink Superset", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            let firstIdx = group.indices.first!
            HStack {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text(names)

                Spacer()
                if let sparkState = states.first(where: { $0.recentWeights.count >= 2 }) {
                    LiftSparklineView(dataPoints: sparkState.recentWeights)
                }
            }
        }
    }

    private func supersetLabel(offset: Int) -> String {
        let letters = "ABCDEFGH"
        guard offset < letters.count else { return "\(offset + 1)" }
        return String(letters[letters.index(letters.startIndex, offsetBy: offset)])
    }

    private func supersetRow(exerciseIndex: Int, setIndex: Int, label: String, state: ExerciseState, isLastInRound: Bool) -> some View {
        SupersetRowView(
            setBinding: $exerciseStates[exerciseIndex].sets[setIndex],
            label: "\(label)\(setIndex + 1)",
            exerciseName: state.exerciseName,
            isMainLift: state.isMainLift,
            isAMRAP: exerciseStates[exerciseIndex].sets[setIndex].isAMRAP,
            restOptions: Self.restOptions,
            restLabel: restLabel,
            onComplete: {
                if isLastInRound {
                    let set = exerciseStates[exerciseIndex].sets[setIndex]
                    startRest(setRestSeconds: set.restSeconds, setType: state.isMainLift ? .main : .accessory)
                }
            }
        )
    }

    // MARK: - Exercise Section Header

    private static let restOptions = [0, 30, 60, 90, 120, 180, 240, 300]

    private func exerciseSectionHeader(for exerciseState: Binding<ExerciseState>) -> some View {
        let state = exerciseState.wrappedValue
        return HStack {
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
            if state.supersetGroup != nil {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }

            Spacer()
            if let lift = state.lift, let cycle {
                let tm = cycle.trainingMax(for: lift)
                let tmPct = userSettings?.tmPercentage(for: lift) ?? 0.9
                let e1rm = tm / tmPct
                VStack(alignment: .trailing, spacing: 0) {
                    Text("E1RM \(Int(e1rm))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("TM \(Int(tm))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if state.recentWeights.count >= 2 {
                LiftSparklineView(dataPoints: state.recentWeights)
            } else if let previousSummary = state.previousBestSummary {
                Text("Prev: \(previousSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setRestPicker(for set: Binding<CompletedSet>, setType: SetType) -> some View {
        let currentRest = set.wrappedValue.restSeconds
        let defaultSecs = defaultRestSeconds(for: setType)
        return Menu {
            Button {
                set.wrappedValue.restSeconds = nil
            } label: {
                HStack {
                    Text("Default (\(restLabel(defaultSecs)))")
                    if currentRest == nil { Image(systemName: "checkmark") }
                }
            }
            ForEach(Self.restOptions.filter { $0 > 0 }, id: \.self) { secs in
                Button {
                    set.wrappedValue.restSeconds = secs
                } label: {
                    HStack {
                        Text(restLabel(secs))
                        if currentRest == secs { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: currentRest != nil ? "timer.circle.fill" : "timer")
                .font(.caption)
                .foregroundStyle(currentRest != nil ? Color.blue : Color.gray)
                .frame(width: 28, height: 28)
        }
    }

    private func restLabel(_ seconds: Int) -> String {
        if seconds >= 60 {
            let min = seconds / 60
            let sec = seconds % 60
            return sec > 0 ? "\(min)m\(sec)s" : "\(min)m"
        }
        return "\(seconds)s"
    }

    // MARK: - Superset Picker

    private var supersetPickerSheet: some View {
        let candidates = exerciseStates.indices.filter { $0 != supersetSourceIndex }
        return NavigationStack {
            List {
                ForEach(candidates, id: \.self) { index in
                    let state = exerciseStates[index]
                    Button {
                        linkSuperset(sourceIndex: supersetSourceIndex!, targetIndex: index)
                        showingSupersetPicker = false
                    } label: {
                        HStack {
                            Text(state.exerciseName)
                            Spacer()
                            if let sg = state.supersetGroup {
                                Text("Superset \(sg)")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Superset With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSupersetPicker = false }
                }
            }
        }
    }

    private func linkSuperset(sourceIndex: Int, targetIndex: Int) {
        let existingGroup = exerciseStates[targetIndex].supersetGroup
            ?? exerciseStates[sourceIndex].supersetGroup
        let group = existingGroup ?? nextSupersetGroupNumber

        exerciseStates[sourceIndex].supersetGroup = group
        exerciseStates[targetIndex].supersetGroup = group
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
        let plateResult = PlateCalculator.calculate(
            totalWeight: set.wrappedValue.weight,
            barWeight: barWeight,
            availablePlates: plates
        )
        return VStack(spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    WeightField(value: set.weight, font: .title3)
                    Text("lbs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if let p = planned {
                    HStack(spacing: 4) {
                        Text("\(Int(p.percentage * 100))% × \(p.reps)\(p.isAMRAP ? "+" : "")\(p.setType == .supplemental ? " \(p.setType.displayName)" : "")")
                            .font(.caption)
                            .foregroundStyle(p.setType == .warmup ? .tertiary : .secondary)
                        if p.setType == .warmup {
                            Text("W")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(.gray)
                                .clipShape(Circle())
                        }
                    }
                    .fixedSize()
                }

                Spacer()

                // Per-set rest picker
                setRestPicker(for: set, setType: state.sets.first?.setType ?? .main)

                // Rep input
                mainRepInput(for: set)
            }

            // Plate visual — tap to toggle
            if !plateResult.plates.isEmpty {
                if showPlatesForSet.contains(set.wrappedValue.id) {
                    PlateVisualView(plateResult: plateResult)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .onTapGesture { showPlatesForSet.remove(set.wrappedValue.id) }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.grid.2x1")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(plateResult.description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .onTapGesture { showPlatesForSet.insert(set.wrappedValue.id) }
                }
            }
        }
        .listRowBackground(
            ZStack(alignment: .top) {
                set.wrappedValue.isComplete ? Color.green.opacity(0.08) : Color.clear
                if set.wrappedValue.isAMRAP {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(height: 3)
                }
            }
        )
    }

    private func mainRepInput(for set: Binding<CompletedSet>, triggerRest: Bool = true) -> some View {
        HStack(spacing: 8) {
            Button {
                if set.wrappedValue.actualReps > 0 {
                    set.wrappedValue.actualReps -= 1
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(set.wrappedValue.actualReps > 0 ? .primary : .quaternary)
            }
            .buttonStyle(.borderless)

            Text("\(set.wrappedValue.isComplete ? set.wrappedValue.actualReps : set.wrappedValue.targetReps)")
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                .frame(minWidth: 36)
                .foregroundStyle(set.wrappedValue.isComplete ? .primary : .tertiary)

            Button {
                if set.wrappedValue.isComplete {
                    set.wrappedValue.actualReps = 0
                } else {
                    set.wrappedValue.actualReps = set.wrappedValue.targetReps
                    if triggerRest {
                        startRest(setRestSeconds: set.wrappedValue.restSeconds, setType: set.wrappedValue.setType)
                    }
                }
            } label: {
                Image(systemName: set.wrappedValue.isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(set.wrappedValue.isComplete ? .green : .accentColor)
            }
            .buttonStyle(.borderless)
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
                previousSet: index < state.previousSets.count ? state.previousSets[index] : nil,
                isBarbell: state.isBarbell
            )
            .onChange(of: exerciseState.sets[index].wrappedValue.actualReps) { oldVal, newVal in
                if oldVal == 0 && newVal > 0 {
                    startRest(setRestSeconds: exerciseState.sets[index].wrappedValue.restSeconds, setType: .accessory)
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

    private func accessorySetRow(setNumber: Int, set: Binding<CompletedSet>, previousSet: CompletedSet?, isBarbell: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Text("\(setNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                // Weight — pre-filled from previous, editable
                WeightField(value: set.weight)
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("lbs")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Reps
                RepsField(value: set.targetReps)
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

            // Plate breakdown for barbell accessories — tap to toggle
            if isBarbell && set.wrappedValue.weight > 0 {
                let plateResult = PlateCalculator.calculate(
                    totalWeight: set.wrappedValue.weight,
                    barWeight: barWeight,
                    availablePlates: plates
                )
                if !plateResult.plates.isEmpty {
                    if showPlatesForSet.contains(set.wrappedValue.id) {
                        PlateVisualView(plateResult: plateResult)
                            .padding(.leading, 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture { showPlatesForSet.remove(set.wrappedValue.id) }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.grid.2x1")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(plateResult.description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.leading, 32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { showPlatesForSet.insert(set.wrappedValue.id) }
                    }
                }
            }
        }
        .listRowBackground(set.wrappedValue.isComplete ? Color.green.opacity(0.08) : nil)
    }

    // MARK: - Rest Timer

    private func autoStartIfNeeded() {
        guard !workoutStarted else { return }
        workoutStartTime = .now
        workoutStarted = true
        UIApplication.shared.isIdleTimerDisabled = true
        phoneConnectivity.sendWorkoutStarted()
    }

    private func startRest(setRestSeconds: Int?, setType: SetType) {
        autoStartIfNeeded()

        // End HR tracking for previous set, start for next
        _ = heartRateManager.markSetEnd()
        heartRateManager.markSetStart()

        // Send workout context to watch
        sendWatchContext()

        let recoveryHR = userSettings?.recoveryHR

        // Use per-set rest if set, otherwise fall back to global defaults
        if let custom = setRestSeconds, custom > 0 {
            restTimer.start(seconds: custom, recoveryHR: recoveryHR)
            phoneConnectivity.sendTimerStarted(totalSeconds: custom, recoveryHR: recoveryHR)
            return
        }

        guard let settings = userSettings else { return }
        let seconds: Int
        switch setType {
        case .warmup:
            seconds = 60
        case .main:
            seconds = settings.defaultRestSeconds
        case .supplemental:
            seconds = settings.supplementalRestSeconds
        case .accessory:
            seconds = settings.accessoryRestSeconds
        case .joker:
            seconds = settings.defaultRestSeconds
        }
        restTimer.start(seconds: seconds, recoveryHR: recoveryHR)
        phoneConnectivity.sendTimerStarted(totalSeconds: seconds, recoveryHR: recoveryHR)
    }

    private func sendWatchContext() {
        // Find the next incomplete set to tell the watch what's coming
        for state in exerciseStates {
            let completedCount = state.sets.filter(\.isComplete).count
            if completedCount < state.sets.count {
                let nextIndex = completedCount
                let set = state.sets[nextIndex]
                phoneConnectivity.sendCurrentExercise(
                    name: state.exerciseName,
                    setNumber: nextIndex + 1,
                    totalSets: state.sets.count,
                    weight: set.weight,
                    targetReps: set.targetReps,
                    isAMRAP: set.isAMRAP,
                    setType: set.setType.rawValue
                )

                // Also send completion progress
                phoneConnectivity.sendSetCompleted(
                    exerciseName: state.exerciseName,
                    setNumber: completedCount,
                    totalSets: state.sets.count,
                    weight: set.weight,
                    reps: set.targetReps,
                    setType: set.setType.rawValue
                )
                return
            }
        }
    }

    /// Complete the next incomplete set (triggered from watch)
    private func completeNextSet() {
        for i in exerciseStates.indices {
            for j in exerciseStates[i].sets.indices {
                if !exerciseStates[i].sets[j].isComplete {
                    exerciseStates[i].sets[j].actualReps = exerciseStates[i].sets[j].targetReps
                    startRest(
                        setRestSeconds: exerciseStates[i].sets[j].restSeconds,
                        setType: exerciseStates[i].sets[j].setType
                    )
                    return
                }
            }
        }
    }

    /// Updates the current incomplete set's reps from watch accelerometer count.
    private func updateCurrentSetReps(_ count: Int) {
        for i in exerciseStates.indices {
            for j in exerciseStates[i].sets.indices {
                if !exerciseStates[i].sets[j].isComplete {
                    exerciseStates[i].sets[j].actualReps = count
                    return
                }
            }
        }
    }

    private func defaultRestSeconds(for setType: SetType) -> Int {
        guard let settings = userSettings else { return 90 }
        switch setType {
        case .warmup: return 60
        case .main: return settings.defaultRestSeconds
        case .supplemental: return settings.supplementalRestSeconds
        case .accessory: return settings.accessoryRestSeconds
        case .joker: return settings.defaultRestSeconds
        }
    }

    // MARK: - Initialize

    private func initializeExercises() {
        // Look up unilateral flags from exercise library
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let exerciseByName = Dictionary(allExercises.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        exerciseStates = template.exerciseEntries
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { entry in
                let previous = PreviousPerformanceLookup.lastPerformance(
                    exerciseName: entry.exerciseName,
                    in: modelContext
                )

                let unilateral = exerciseByName[entry.exerciseName]?.isUnilateral ?? false

                let equipment = exerciseByName[entry.exerciseName]?.equipmentType ?? "barbell"

                var state = ExerciseState(
                    id: entry.id,
                    exerciseName: entry.exerciseName,
                    mainLift: entry.mainLift,
                    sets: [],
                    plannedSets: [],
                    previousSets: previous?.sets ?? [],
                    previousBestSummary: previous?.bestSetSummary,
                    supersetGroup: entry.supersetGroup,
                    isUnilateral: unilateral,
                    equipmentType: equipment
                )

                if let lift = entry.lift, let cycle {
                    let tm = cycle.trainingMax(for: lift)
                    let warmupScheme = userSettings?.warmupScheme ?? [(0.40, 5), (0.50, 5), (0.60, 3)]
                    let warmupPlanned = ProgramEngine.warmupSets(
                        trainingMax: tm, scheme: warmupScheme, roundTo: roundTo
                    )
                    let mainPlanned = ProgramEngine.mainSets(
                        trainingMax: tm, week: week,
                        variant: cycle.programVariant, roundTo: roundTo
                    )
                    let suppPlanned = ProgramEngine.supplementalSets(
                        trainingMax: tm, week: week,
                        variant: cycle.programVariant, roundTo: roundTo
                    )
                    let allPlanned = warmupPlanned + mainPlanned + suppPlanned
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

                // Load recent weights for sparkline
                state.recentWeights = PreviousPerformanceLookup.recentTopSets(
                    exerciseName: entry.exerciseName,
                    in: modelContext
                )

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
                sortOrder: index,
                supersetGroup: state.supersetGroup,
                isUnilateral: state.isUnilateral
            )
        }

        // Compute HR stats
        let avgHR = heartRateManager.sessionAverageHR
        let durationMinutes = Double(duration) / 60.0
        let weightKg = (userSettings?.bodyWeightLbs ?? 176) / 2.205
        let age = userSettings?.userAge ?? 30
        let isMale = userSettings?.isMale ?? true
        let calories: Double? = if let avgHR {
            HeartRateManager.estimateCalories(
                averageHR: avgHR,
                durationMinutes: durationMinutes,
                bodyWeightKg: weightKg,
                age: age,
                isMale: isMale
            )
        } else {
            nil
        }

        let workout = CompletedWorkout(
            date: .now,
            templateName: template.name,
            cycleNumber: cycle?.number ?? 0,
            weekNumber: week,
            exercisePerformances: performances,
            notes: notes,
            durationSeconds: duration,
            variant: cycle?.programVariant ?? .standard,
            averageHeartRate: avgHR,
            estimatedCalories: calories
        )
        modelContext.insert(workout)
        restTimer.stop()
        heartRateManager.stopMonitoring()
        UIApplication.shared.isIdleTimerDisabled = false
        phoneConnectivity.sendWorkoutFinished()

        // Save to HealthKit
        let startTime = workoutStartTime ?? .now
        let endTime = Date.now
        let savedCalories = calories
        let savedAvgHR = avgHR
        Task {
            await heartRateManager.saveWorkoutToHealthKit(
                start: startTime,
                end: endTime,
                calories: savedCalories,
                averageHR: savedAvgHR
            )
        }

        // Detect changes to the template
        templateChanges = detectTemplateChanges()
        if templateChanges.hasChanges {
            showingSaveTemplateSheet = true
        } else {
            dismiss()
        }
    }

    // MARK: - Template Change Detection

    private func detectTemplateChanges() -> TemplateChanges {
        var changes = TemplateChanges()
        let originalEntries = template.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })
        let originalNames = originalEntries.map { $0.exerciseName }
        let currentNames = exerciseStates.map { $0.exerciseName }

        // Check reordering
        if originalNames != currentNames {
            // Could be reorder, additions, or both
            let originalSet = Set(originalNames)
            let currentSet = Set(currentNames)

            // New exercises added during workout
            let added = currentSet.subtracting(originalSet)
            if !added.isEmpty {
                changes.newExercises = exerciseStates.filter { added.contains($0.exerciseName) }
                    .map { $0.exerciseName }
            }

            // Check if order changed (comparing only exercises that exist in both)
            let commonOriginal = originalNames.filter { currentSet.contains($0) }
            let commonCurrent = currentNames.filter { originalSet.contains($0) }
            if commonOriginal != commonCurrent {
                changes.orderChanged = true
            }
        }

        // Check accessory weight/rep changes
        for state in exerciseStates where !state.isMainLift {
            if let originalEntry = originalEntries.first(where: { $0.exerciseName == state.exerciseName }) {
                // Compare completed sets against previous sets
                let completedSets = state.sets.filter { $0.isComplete }
                if !completedSets.isEmpty {
                    changes.exercisesWithNewValues.append(state.exerciseName)
                }
            }
        }

        // Check set count changes for accessories
        for state in exerciseStates where !state.isMainLift {
            let originalPrev = state.previousSets.count
            let current = state.sets.count
            if current != originalPrev && current != 3 { // 3 is the default
                changes.setCountChanged = true
            }
        }

        // Check superset changes
        let originalSupersets = Dictionary(
            uniqueKeysWithValues: originalEntries.map { ($0.exerciseName, $0.supersetGroup) }
        )
        for state in exerciseStates {
            let original = originalSupersets[state.exerciseName] ?? nil
            if state.supersetGroup != original {
                changes.supersetsChanged = true
                break
            }
        }

        return changes
    }

    private func applyTemplateChanges(_ selections: TemplateChangeSelections) {
        var updatedEntries = template.exerciseEntries

        if selections.saveOrder {
            updatedEntries = exerciseStates.enumerated().map { index, state in
                if var existing = updatedEntries.first(where: { $0.id == state.id }) {
                    existing.sortOrder = index
                    return existing
                }
                return TemplateExerciseEntry(
                    exerciseName: state.exerciseName,
                    mainLift: state.mainLift,
                    sortOrder: index,
                    supersetGroup: state.supersetGroup
                )
            }
        }

        if selections.saveNewExercises {
            let existingNames = Set(updatedEntries.map { $0.exerciseName })
            let maxOrder = (updatedEntries.map { $0.sortOrder }.max() ?? -1) + 1
            for (offset, state) in exerciseStates.enumerated() where !existingNames.contains(state.exerciseName) {
                updatedEntries.append(TemplateExerciseEntry(
                    exerciseName: state.exerciseName,
                    mainLift: state.mainLift,
                    sortOrder: selections.saveOrder ? offset : maxOrder + offset,
                    supersetGroup: state.supersetGroup
                ))
            }
        }

        if selections.saveSupersets {
            for i in updatedEntries.indices {
                if let state = exerciseStates.first(where: { $0.id == updatedEntries[i].id }) {
                    updatedEntries[i].supersetGroup = state.supersetGroup
                }
            }
        }

        template.exerciseEntries = updatedEntries
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
    var recentWeights: [(date: Date, weight: Double)] = []
    var supersetGroup: Int?
    var isUnilateral: Bool = false
    var equipmentType: String = "barbell"

    var isMainLift: Bool { mainLift != nil }
    var isBarbell: Bool { equipmentType == "barbell" }
    var lift: Lift? { mainLift.flatMap { Lift(rawValue: $0) } }
}

// MARK: - Exercise Section Group

struct ExerciseSectionGroup: Identifiable {
    let id = UUID()
    let indices: [Int]
    let supersetGroup: Int?
}

// MARK: - Template Changes

struct TemplateChanges {
    var orderChanged = false
    var newExercises: [String] = []
    var exercisesWithNewValues: [String] = []
    var setCountChanged = false
    var supersetsChanged = false

    var hasChanges: Bool {
        orderChanged || !newExercises.isEmpty || supersetsChanged
    }
}

struct TemplateChangeSelections {
    var saveOrder = true
    var saveNewExercises = true
    var saveSupersets = true
}

// MARK: - Save Template Changes Sheet

struct SaveTemplateChangesView: View {
    let changes: TemplateChanges
    let onSave: (TemplateChangeSelections) -> Void
    let onSkip: () -> Void

    @State private var selections = TemplateChangeSelections()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your workout had changes from the template. Save them for next time?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)

                Section("Changes Detected") {
                    if changes.orderChanged {
                        Toggle(isOn: $selections.saveOrder) {
                            VStack(alignment: .leading) {
                                Text("Exercise order")
                                    .font(.body)
                                Text("Update the exercise order in the template")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !changes.newExercises.isEmpty {
                        Toggle(isOn: $selections.saveNewExercises) {
                            VStack(alignment: .leading) {
                                Text("New exercises")
                                    .font(.body)
                                Text(changes.newExercises.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if changes.supersetsChanged {
                        Toggle(isOn: $selections.saveSupersets) {
                            VStack(alignment: .leading) {
                                Text("Superset groupings")
                                    .font(.body)
                                Text("Update which exercises are supersetted")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Update Template?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selections)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                    }
                }
            }
        }
    }
}

// MARK: - Workout Bottom Bar

struct WorkoutBottomBar: View {
    @Bindable var restTimer: RestTimerState
    var heartRateManager: HeartRateManager
    @Binding var workoutStartTime: Date?

    @State private var elapsed: TimeInterval = 0
    @State private var elapsedTimer: Timer?

    var body: some View {
        VStack(spacing: 6) {
            // Top row: workout timer + HR
            HStack {
                // Workout elapsed time
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedElapsed)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                Spacer()

                // Heart rate
                if heartRateManager.isMonitoring && heartRateManager.currentHR > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("\(Int(heartRateManager.currentHR))")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .monospacedDigit()
                        if let avg = heartRateManager.sessionAverageHR {
                            Text("avg \(Int(avg))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Rest timer (only when active)
            if restTimer.isRunning {
                RestTimerView(timer: restTimer, currentHR: heartRateManager.currentHR)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onAppear { startElapsedTimer() }
        .onDisappear { elapsedTimer?.invalidate() }
    }

    private var formattedElapsed: String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startElapsedTimer() {
        updateElapsed()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateElapsed()
            }
        }
    }

    private func updateElapsed() {
        guard let start = workoutStartTime else { return }
        elapsed = Date.now.timeIntervalSince(start)
    }
}

// MARK: - Superset Row View

/// Separate view so bindings are read reactively in body (not captured as lets).
struct SupersetRowView: View {
    @Binding var setBinding: CompletedSet
    let label: String
    let exerciseName: String
    let isMainLift: Bool
    let isAMRAP: Bool
    let restOptions: [Int]
    let restLabel: (Int) -> String
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.purple)
                .frame(width: 24)

            Text(exerciseName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            WeightField(value: $setBinding.weight, width: 55)
                .padding(4)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if isMainLift {
                Spacer()
                supersetRestMenu
                supersetRepStepper
            } else {
                RepsField(value: $setBinding.targetReps, width: 35)
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                supersetRestMenu

                Button {
                    let wasComplete = setBinding.isComplete
                    if wasComplete {
                        setBinding.actualReps = 0
                    } else {
                        setBinding.actualReps = setBinding.targetReps
                        onComplete()
                    }
                } label: {
                    Image(systemName: setBinding.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(setBinding.isComplete ? .green : .secondary)
                }
            }
        }
        .listRowBackground(
            ZStack(alignment: .top) {
                setBinding.isComplete ? Color.green.opacity(0.08) : Color.clear
                if isAMRAP {
                    Rectangle().fill(Color.orange).frame(height: 3)
                }
            }
        )
    }

    private var supersetRestMenu: some View {
        let currentRest = setBinding.restSeconds
        return Menu {
            Button {
                setBinding.restSeconds = nil
            } label: {
                HStack {
                    Text("Default")
                    if currentRest == nil { Image(systemName: "checkmark") }
                }
            }
            ForEach(restOptions.filter { $0 > 0 }, id: \.self) { secs in
                Button {
                    setBinding.restSeconds = secs
                } label: {
                    HStack {
                        Text(restLabel(secs))
                        if currentRest == secs { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: currentRest != nil ? "timer.circle.fill" : "timer")
                .font(.caption)
                .foregroundStyle(currentRest != nil ? Color.blue : Color.gray)
                .frame(width: 28, height: 28)
        }
    }

    private var supersetRepStepper: some View {
        HStack(spacing: 8) {
            Button {
                if setBinding.actualReps > 0 {
                    setBinding.actualReps -= 1
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(setBinding.actualReps > 0 ? .primary : .quaternary)
            }
            .buttonStyle(.borderless)

            Text("\(setBinding.isComplete ? setBinding.actualReps : setBinding.targetReps)")
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                .frame(minWidth: 36)
                .foregroundStyle(setBinding.isComplete ? .primary : .tertiary)

            Button {
                if setBinding.isComplete {
                    setBinding.actualReps = 0
                } else {
                    setBinding.actualReps = setBinding.targetReps
                    onComplete()
                }
            } label: {
                Image(systemName: setBinding.isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(setBinding.isComplete ? .green : .accentColor)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Weight Text Field

/// A text field that binds to a Double but allows free-form numeric text entry
/// without rejecting intermediate states (empty, trailing decimal, etc.)
struct WeightField: View {
    @Binding var value: Double
    var width: CGFloat = 48
    var font: Font = .body

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("0", text: $text)
            .font(font)
            .fontWeight(.medium)
            .monospacedDigit()
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .frame(width: width)
            .focused($isFocused)
            .onAppear { text = formatValue(value) }
            .onChange(of: value) { _, newVal in
                if !isFocused {
                    text = formatValue(newVal)
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    // Commit on blur
                    value = Double(text) ?? 0
                    text = formatValue(value)
                }
            }
    }

    private func formatValue(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// Same pattern for integer fields (reps)
struct RepsField: View {
    @Binding var value: Int
    var width: CGFloat = 40

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("0", text: $text)
            .font(.body)
            .fontWeight(.medium)
            .monospacedDigit()
            .keyboardType(.numberPad)
            .textFieldStyle(.plain)
            .frame(width: width)
            .focused($isFocused)
            .onAppear { text = value > 0 ? "\(value)" : "" }
            .onChange(of: value) { _, newVal in
                if !isFocused {
                    text = newVal > 0 ? "\(newVal)" : ""
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    value = Int(text) ?? 0
                    text = value > 0 ? "\(value)" : ""
                }
            }
    }
}
