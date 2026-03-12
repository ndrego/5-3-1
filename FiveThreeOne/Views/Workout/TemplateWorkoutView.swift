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
    private var phoneConnectivity: PhoneConnectivityManager { .shared }
    @State private var showPlatesForSet: Set<UUID> = []
    @State private var showRepTuning = false
    @State private var selectedExerciseForDetail: String?
    @State private var showDiscardConfirmation = false
    @State private var detectedRepCounts: [UUID: Int] = [:]
    @State private var activeTimerSetID: UUID?
    @State private var timerSecondsRemaining: Int = 0
    @State private var exerciseTimerTask: Task<Void, Never>?

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
                            let repEnabled = userSettings?.repCountingEnabled ?? false
                            phoneConnectivity.sendRepCountingEnabled(repEnabled)
                            if repEnabled {
                                phoneConnectivity.sendRepTuning(
                                    sensitivity: userSettings?.repSensitivity ?? [:],
                                    tempo: userSettings?.repTempo ?? [:]
                                )
                            }
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

                        Button(role: .destructive) {
                            showDiscardConfirmation = true
                        } label: {
                            Label("Cancel Workout", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
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
        .navigationBarBackButtonHidden(workoutStarted)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Workout in Progress", isPresented: $showDiscardConfirmation) {
            Button("Discard Workout", role: .destructive) {
                UIApplication.shared.isIdleTimerDisabled = false
                phoneConnectivity.sendWorkoutFinished()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have a workout in progress. Are you sure you want to leave? Your progress will be lost.")
        }
        .toolbar {
            if workoutStarted {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiscardConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                                .font(.callout)
                            Text("Back")
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if workoutStarted && (userSettings?.repCountingEnabled ?? false) {
                        Button {
                            showRepTuning = true
                        } label: {
                            Image(systemName: "waveform.badge.magnifyingglass")
                        }
                    }
                    Button(isReordering ? "Done" : "Reorder") {
                        withAnimation {
                            isReordering.toggle()
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            initializeExercises()
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
            // Start tracking HR samples immediately so the first set has data
            heartRateManager.markSetStart()
        }
        .onChange(of: phoneConnectivity.watchHeartRateUpdateCount) {
            let bpm = phoneConnectivity.watchHeartRate
            if bpm > 0 {
                heartRateManager.recordBPM(bpm)
            }
        }
        .onChange(of: phoneConnectivity.isWatchReachable) { _, reachable in
            if reachable && workoutStarted {
                phoneConnectivity.sendWorkoutStarted()
                sendWatchContext()
            }
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
        .sheet(isPresented: Binding(
            get: { selectedExerciseForDetail != nil },
            set: { if !$0 { selectedExerciseForDetail = nil } }
        )) {
            if let name = selectedExerciseForDetail {
                NavigationStack {
                    ExerciseDetailView(exerciseName: name)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { selectedExerciseForDetail = nil }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showRepTuning) {
            RepCountingTuningView { sensitivity, tempo in
                phoneConnectivity.sendRepTuning(sensitivity: sensitivity, tempo: tempo)
            }
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

            HStack {
                // Superset link button
                Button {
                    supersetSourceIndex = index
                    showingSupersetPicker = true
                } label: {
                    Label("Superset with...", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }

                Spacer()

                // Remove exercise button (not for main lifts)
                if !state.isMainLift {
                    Button(role: .destructive) {
                        let idx = index
                        withAnimation {
                            _ = exerciseStates.remove(at: idx)
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            exerciseSectionHeader(for: $exerciseStates[index])
        }
    }

    // MARK: - Superset Section (interleaved)

    /// Build the list of (exerciseIndex, setIndex) pairs for each round in a superset,
    /// handling sub-groups that alternate across rounds.
    private func supersetRounds(for group: ExerciseSectionGroup) -> [[(exerciseIndex: Int, setIndex: Int)]] {
        let states = group.indices.map { exerciseStates[$0] }
        let hasSubGroups = states.contains { $0.supersetSubGroup != nil }

        if !hasSubGroups {
            // Standard: all exercises every round
            let maxSets = states.map { $0.sets.count }.max() ?? 0
            return (0..<maxSets).map { setIndex in
                group.indices.compactMap { idx in
                    let state = exerciseStates[idx]
                    guard setIndex < state.sets.count else { return nil }
                    return (exerciseIndex: idx, setIndex: setIndex)
                }
            }
        }

        // Sub-group mode: exercises with nil sub-group appear every round,
        // numbered sub-groups alternate
        let everyRound = group.indices.filter { exerciseStates[$0].supersetSubGroup == nil }
        let subGroupKeys = Array(Set(group.indices.compactMap { exerciseStates[$0].supersetSubGroup })).sorted()
        guard !subGroupKeys.isEmpty else {
            // All nil sub-groups — fall back to standard
            let maxSets = states.map { $0.sets.count }.max() ?? 0
            return (0..<maxSets).map { setIndex in
                group.indices.compactMap { idx in
                    guard setIndex < exerciseStates[idx].sets.count else { return nil }
                    return (exerciseIndex: idx, setIndex: setIndex)
                }
            }
        }

        let maxSets = states.map { $0.sets.count }.max() ?? 0
        var setCounters: [Int: Int] = [:] // exerciseIndex -> next set index
        for idx in group.indices { setCounters[idx] = 0 }

        var rounds: [[(exerciseIndex: Int, setIndex: Int)]] = []
        for round in 0..<maxSets {
            let activeKey = subGroupKeys[round % subGroupKeys.count]
            let activeIndices = group.indices.filter { exerciseStates[$0].supersetSubGroup == activeKey }
            let roundIndices = everyRound + activeIndices

            var roundEntries: [(exerciseIndex: Int, setIndex: Int)] = []
            for idx in roundIndices {
                let setIdx = setCounters[idx] ?? 0
                guard setIdx < exerciseStates[idx].sets.count else { continue }
                roundEntries.append((exerciseIndex: idx, setIndex: setIdx))
                setCounters[idx] = setIdx + 1
            }
            if !roundEntries.isEmpty {
                rounds.append(roundEntries)
            }
        }
        return rounds
    }

    @ViewBuilder
    private func supersetSection(for group: ExerciseSectionGroup) -> some View {
        let states = group.indices.map { exerciseStates[$0] }
        let names = states.map { $0.exerciseName }.joined(separator: " + ")
        let rounds = supersetRounds(for: group)

        Section {
            ForEach(Array(rounds.enumerated()), id: \.offset) { roundIdx, entries in
                ForEach(Array(entries.enumerated()), id: \.offset) { entryIdx, entry in
                    let state = exerciseStates[entry.exerciseIndex]
                    let labelOffset = group.indices.firstIndex(of: entry.exerciseIndex) ?? 0
                    supersetRow(
                        exerciseIndex: entry.exerciseIndex,
                        setIndex: entry.setIndex,
                        label: supersetLabel(offset: labelOffset),
                        state: state,
                        isLastInRound: entryIdx == entries.count - 1
                    )
                }
            }

            HStack {
                // Add exercise to this superset
                Button {
                    supersetSourceIndex = group.indices.first
                    showingSupersetPicker = true
                } label: {
                    Label("Add to superset", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }

                Spacer()

                // Unlink button
                Button {
                    for idx in group.indices {
                        exerciseStates[idx].supersetGroup = nil
                    }
                } label: {
                    Label("Unlink", systemImage: "link.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
        let setID = exerciseStates[exerciseIndex].sets[setIndex].id
        return SupersetRowView(
            setBinding: $exerciseStates[exerciseIndex].sets[setIndex],
            label: "\(label)\(setIndex + 1)",
            exerciseName: state.exerciseName,
            isMainLift: state.isMainLift,
            isAMRAP: exerciseStates[exerciseIndex].sets[setIndex].isAMRAP,
            isTimed: state.isTimed,
            isLastInRound: isLastInRound,
            restOptions: Self.restOptions,
            restLabel: restLabel,
            onComplete: {
                if isLastInRound {
                    let set = exerciseStates[exerciseIndex].sets[setIndex]
                    startRest(setRestSeconds: set.restSeconds, setType: state.isMainLift ? .main : .accessory)
                }
            },
            onUnmark: {
                sendWatchContext()
            },
            isTimerActive: activeTimerSetID == setID,
            timerSecondsRemaining: activeTimerSetID == setID ? timerSecondsRemaining : 0,
            onStartTimer: {
                startExerciseTimer(set: $exerciseStates[exerciseIndex].sets[setIndex])
            },
            onStopTimer: {
                stopExerciseTimer()
            }
        )
    }

    // MARK: - Exercise Section Header

    private static let restOptions = [0, 30, 60, 90, 120, 180, 240, 300]

    private func exerciseSectionHeader(for exerciseState: Binding<ExerciseState>) -> some View {
        let state = exerciseState.wrappedValue
        return HStack {
            Button(state.exerciseName) {
                selectedExerciseForDetail = state.exerciseName
            }
            .buttonStyle(.plain)
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

    private func supersetPickerCandidates() -> (standalone: [Int], groupReps: [(index: Int, group: Int, names: String)]) {
        let sourceIdx = supersetSourceIndex ?? 0
        let sourceGroup = exerciseStates[sourceIdx].supersetGroup
        let candidates = exerciseStates.indices.filter { $0 != sourceIdx }

        let standalone = candidates.filter { exerciseStates[$0].supersetGroup == nil }

        var seenGroups = Set<Int>()
        var groupReps: [(index: Int, group: Int, names: String)] = []
        for idx in candidates {
            guard let g = exerciseStates[idx].supersetGroup, g != sourceGroup else { continue }
            guard seenGroups.insert(g).inserted else { continue }
            let names = exerciseStates.filter { $0.supersetGroup == g }.map(\.exerciseName).joined(separator: " + ")
            groupReps.append((index: idx, group: g, names: names))
        }
        return (standalone, groupReps)
    }

    private var supersetPickerSheet: some View {
        let sourceIdx = supersetSourceIndex ?? 0
        let (standalone, groupReps) = supersetPickerCandidates()

        return NavigationStack {
            List {
                if !groupReps.isEmpty {
                    Section("Add to Existing Superset") {
                        ForEach(groupReps, id: \.group) { rep in
                            Button {
                                linkSuperset(sourceIndex: sourceIdx, targetIndex: rep.index)
                                showingSupersetPicker = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rep.names)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }

                Section(groupReps.isEmpty ? "Superset With" : "Create New Superset") {
                    ForEach(standalone, id: \.self) { index in
                        Button {
                            linkSuperset(sourceIndex: sourceIdx, targetIndex: index)
                            showingSupersetPicker = false
                        } label: {
                            Text(exerciseStates[index].exerciseName)
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

        Button {
            let lastSet = state.sets.last
            let newSet = CompletedSet(
                weight: lastSet?.weight ?? 0,
                targetReps: lastSet?.targetReps ?? 1,
                isAMRAP: false,
                setType: lastSet?.setType ?? .main
            )
            exerciseState.wrappedValue.sets.append(newSet)
        } label: {
            Label("Add Set", systemImage: "plus.circle")
                .font(.subheadline)
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

            // HR + RPE after set completion
            if set.wrappedValue.isComplete, let avgHR = set.wrappedValue.averageHR {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                        Text("\(Int(avgHR))")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    if let rpe = set.wrappedValue.estimatedRPE {
                        Text("RPE \(String(format: "%.1f", rpe))")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(rpeColor(rpe))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
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

            VStack(spacing: 2) {
                Text("\(set.wrappedValue.isComplete ? set.wrappedValue.actualReps : set.wrappedValue.targetReps)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .frame(minWidth: 36)
                    .foregroundStyle(set.wrappedValue.isComplete ? .primary : .tertiary)

                if !set.wrappedValue.isComplete, let detected = detectedRepCounts[set.wrappedValue.id], detected > 0 {
                    Text("\(detected) detected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if set.wrappedValue.isComplete {
                    set.wrappedValue.actualReps = 0
                    sendWatchContext()
                } else {
                    let detected = detectedRepCounts[set.wrappedValue.id]
                    set.wrappedValue.actualReps = detected ?? set.wrappedValue.targetReps
                    detectedRepCounts.removeValue(forKey: set.wrappedValue.id)
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
                isBarbell: state.isBarbell,
                isTimed: state.isTimed
            )
            .onChange(of: exerciseState.sets[index].wrappedValue.actualReps) { oldVal, newVal in
                if oldVal == 0 && newVal > 0 {
                    startRest(setRestSeconds: exerciseState.sets[index].wrappedValue.restSeconds, setType: .accessory)
                }
            }
            .swipeActions(edge: .trailing) {
                if state.sets.count > 1 {
                    Button(role: .destructive) {
                        exerciseState.wrappedValue.sets.remove(at: index)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }

        Button {
            let prevSet = state.previousSets.count > state.sets.count
                ? state.previousSets[state.sets.count]
                : state.sets.last
            let defaultTarget = state.isTimed ? 30 : 10
            let newSet = CompletedSet(
                weight: state.isTimed ? 0 : (prevSet?.weight ?? 0),
                targetReps: prevSet?.actualReps ?? defaultTarget,
                setType: .accessory
            )
            exerciseState.wrappedValue.sets.append(newSet)
        } label: {
            Label("Add Set", systemImage: "plus.circle")
                .font(.subheadline)
        }
    }

    private func accessorySetRow(setNumber: Int, set: Binding<CompletedSet>, previousSet: CompletedSet?, isBarbell: Bool = false, isTimed: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Text("\(setNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                if !isTimed {
                    // Weight — pre-filled from previous, editable
                    WeightField(value: set.weight)
                        .padding(4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("lbs")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Reps or seconds
                RepsField(value: set.targetReps)
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(isTimed ? "sec" : "reps")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if isTimed {
                    timedSetButton(set: set)
                } else {
                    // Tap to confirm: copies targetReps → actualReps
                    Button {
                        if set.wrappedValue.isComplete {
                            set.wrappedValue.actualReps = 0
                            sendWatchContext()
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

    // MARK: - Exercise Timer (Plank, etc.)

    @ViewBuilder
    private func timedSetButton(set: Binding<CompletedSet>) -> some View {
        let setID = set.wrappedValue.id
        let isTimerActive = activeTimerSetID == setID

        if set.wrappedValue.isComplete {
            // Already done — tap to undo
            Button {
                set.wrappedValue.actualReps = 0
                sendWatchContext()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            .frame(width: 44, height: 44)
        } else if isTimerActive {
            // Timer running — show countdown, tap to cancel
            Button {
                stopExerciseTimer()
            } label: {
                Text(formatExerciseTimer(timerSecondsRemaining))
                    .font(.body.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
            .frame(minWidth: 54, minHeight: 44)
        } else {
            // Not started — tap to start countdown
            Button {
                startExerciseTimer(set: set)
            } label: {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .frame(width: 44, height: 44)
        }
    }

    private func startExerciseTimer(set: Binding<CompletedSet>) {
        stopExerciseTimer()
        let seconds = set.wrappedValue.targetReps
        guard seconds > 0 else { return }
        activeTimerSetID = set.wrappedValue.id
        timerSecondsRemaining = seconds

        // Capture the set ID to match later
        let setID = set.wrappedValue.id
        exerciseTimerTask = Task {
            while !Task.isCancelled && timerSecondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                timerSecondsRemaining -= 1
            }
            if !Task.isCancelled && timerSecondsRemaining <= 0 {
                // Timer finished — complete the set
                activeTimerSetID = nil
                // Find and complete the set by ID
                for i in exerciseStates.indices {
                    if let j = exerciseStates[i].sets.firstIndex(where: { $0.id == setID }) {
                        exerciseStates[i].sets[j].actualReps = exerciseStates[i].sets[j].targetReps
                        startRest(setRestSeconds: exerciseStates[i].sets[j].restSeconds, setType: .accessory)
                        break
                    }
                }
            }
        }
    }

    private func stopExerciseTimer() {
        exerciseTimerTask?.cancel()
        exerciseTimerTask = nil
        activeTimerSetID = nil
    }

    private func formatExerciseTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
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

        // End HR tracking for previous set, store data on it
        if let hrResult = heartRateManager.markSetEnd() {
            let age = userSettings?.userAge ?? 30
            let rpe = HeartRateManager.estimateRPE(heartRate: hrResult.average, age: age)
            storeHROnLastCompletedSet(average: hrResult.average, samples: hrResult.samples, rpe: rpe)
        }
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
                    setType: set.setType.rawValue,
                    repCountingEnabled: userSettings?.repCountingEnabled ?? false
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
                    let setId = exerciseStates[i].sets[j].id
                    let detected = detectedRepCounts[setId]
                    exerciseStates[i].sets[j].actualReps = detected ?? exerciseStates[i].sets[j].targetReps
                    detectedRepCounts.removeValue(forKey: setId)
                    startRest(
                        setRestSeconds: exerciseStates[i].sets[j].restSeconds,
                        setType: exerciseStates[i].sets[j].setType
                    )
                    return
                }
            }
        }
    }

    private func rpeColor(_ rpe: Double) -> Color {
        switch rpe {
        case ..<7: return .green
        case ..<8: return .yellow
        case ..<9: return .orange
        default: return .red
        }
    }

    /// Stores HR data on the most recently completed set that doesn't have HR yet.
    private func storeHROnLastCompletedSet(average: Double, samples: [Double], rpe: Double) {
        for i in exerciseStates.indices.reversed() {
            for j in exerciseStates[i].sets.indices.reversed() {
                if exerciseStates[i].sets[j].isComplete && exerciseStates[i].sets[j].averageHR == nil {
                    exerciseStates[i].sets[j].averageHR = average
                    exerciseStates[i].sets[j].hrSamples = samples
                    exerciseStates[i].sets[j].estimatedRPE = rpe
                    return
                }
            }
        }
    }

    /// Updates the detected rep count from the watch accelerometer (display-only, does not complete the set).
    private func updateCurrentSetReps(_ count: Int) {
        for i in exerciseStates.indices {
            for j in exerciseStates[i].sets.indices {
                if !exerciseStates[i].sets[j].isComplete {
                    detectedRepCounts[exerciseStates[i].sets[j].id] = count
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
                let timed = exerciseByName[entry.exerciseName]?.isTimed ?? false

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
                    equipmentType: equipment,
                    isTimed: timed,
                    supersetSubGroup: entry.supersetSubGroup
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
                    let defaultTarget = timed ? 30 : 10
                    let templateSets = entry.defaultSets
                    let setCount = templateSets ?? max(previous?.sets.count ?? 3, 3)
                    state.sets = (0..<setCount).map { i in
                        let prev = i < (previous?.sets.count ?? 0) ? previous?.sets[i] : nil
                        let target: Int
                        if timed {
                            // Use previous targetReps if it looks like seconds (>=15), otherwise default
                            let prevTarget = prev?.targetReps ?? 0
                            target = prevTarget >= 15 ? prevTarget : defaultTarget
                        } else {
                            target = prev?.actualReps ?? defaultTarget
                        }
                        return CompletedSet(
                            weight: timed ? 0 : (prev?.weight ?? 0),
                            targetReps: target,
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
                    updatedEntries[i].supersetSubGroup = state.supersetSubGroup
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
    var isTimed: Bool = false
    var supersetSubGroup: Int? = nil

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
                    .onChange(of: restTimer.totalSeconds) {
                        PhoneConnectivityManager.shared.sendTimerAdjusted(
                            remainingSeconds: restTimer.remainingSeconds,
                            totalSeconds: restTimer.totalSeconds
                        )
                    }
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
    let isTimed: Bool
    let isLastInRound: Bool
    let restOptions: [Int]
    let restLabel: (Int) -> String
    let onComplete: () -> Void
    var onUnmark: (() -> Void)?
    // Timer state for timed exercises (passed from parent)
    var isTimerActive: Bool = false
    var timerSecondsRemaining: Int = 0
    var onStartTimer: (() -> Void)?
    var onStopTimer: (() -> Void)?

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

            if !isTimed {
                WeightField(value: $setBinding.weight, width: 55)
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if isMainLift {
                Spacer()
                if isLastInRound { supersetRestMenu }
                supersetRepStepper
            } else {
                RepsField(value: $setBinding.targetReps, width: 35)
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if isTimed {
                    Text("sec")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isLastInRound { supersetRestMenu }

                if isTimed {
                    timedButton
                } else {
                    Button {
                        if setBinding.isComplete {
                            setBinding.actualReps = 0
                            onUnmark?()
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

    @ViewBuilder
    private var timedButton: some View {
        if setBinding.isComplete {
            Button {
                setBinding.actualReps = 0
                onUnmark?()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
        } else if isTimerActive {
            Button {
                onStopTimer?()
            } label: {
                let m = timerSecondsRemaining / 60
                let s = timerSecondsRemaining % 60
                Text(m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
            .frame(minWidth: 44)
        } else {
            Button {
                onStartTimer?()
            } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
        }
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
                    onUnmark?()
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
