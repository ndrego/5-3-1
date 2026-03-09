import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]
    @Query(sort: \Cycle.number, order: .reverse) private var cycles: [Cycle]

    @State private var showingTMSetup = false
    @State private var showingImport = false
    @State private var showingBackup = false
    @State private var showingNewCycleSheet = false

    private var userSettings: UserSettings? { settings.first }
    private var currentCycle: Cycle? { cycles.first(where: { !$0.isComplete }) ?? cycles.first }

    private static let barWeightOptions: [Double] = [33, 35, 44, 45, 55, 65]
    private static let roundToOptions: [Double] = [1, 2.5, 5, 10]
    private static let restOptions = [30, 45, 60, 90, 120, 150, 180, 210, 240, 300]
    private static let recoveryHROptions = [100, 110, 120, 130, 140]

    var body: some View {
        NavigationStack {
            Form {
                if let s = userSettings {
                    Section("Equipment") {
                        Picker("Bar Weight", selection: Binding(
                            get: { s.barWeight },
                            set: { s.barWeight = $0 }
                        )) {
                            ForEach(Self.barWeightOptions, id: \.self) { w in
                                Text("\(formatWeight(w)) lbs").tag(w)
                            }
                        }

                        Picker("Round To", selection: Binding(
                            get: { s.roundTo },
                            set: { s.roundTo = $0 }
                        )) {
                            ForEach(Self.roundToOptions, id: \.self) { r in
                                Text("\(formatWeight(r)) lbs").tag(r)
                            }
                        }
                    }

                    Section("Rest Timers") {
                        Picker("Main Sets", selection: Binding(
                            get: { s.defaultRestSeconds },
                            set: { s.defaultRestSeconds = $0 }
                        )) {
                            ForEach(Self.restOptions, id: \.self) { secs in
                                Text(restLabel(secs)).tag(secs)
                            }
                        }

                        Picker("Supplemental", selection: Binding(
                            get: { s.supplementalRestSeconds },
                            set: { s.supplementalRestSeconds = $0 }
                        )) {
                            ForEach(Self.restOptions, id: \.self) { secs in
                                Text(restLabel(secs)).tag(secs)
                            }
                        }

                        Picker("Accessory", selection: Binding(
                            get: { s.accessoryRestSeconds },
                            set: { s.accessoryRestSeconds = $0 }
                        )) {
                            ForEach(Self.restOptions, id: \.self) { secs in
                                Text(restLabel(secs)).tag(secs)
                            }
                        }

                        Picker("Recovery HR", selection: Binding(
                            get: { s.recoveryHR ?? 0 },
                            set: { s.recoveryHR = $0 == 0 ? nil : $0 }
                        )) {
                            Text("Off").tag(0)
                            ForEach(Self.recoveryHROptions, id: \.self) { hr in
                                Text("\(hr) BPM").tag(hr)
                            }
                        }
                    }

                    Section("Body Stats") {
                        Picker("Age", selection: Binding(
                            get: { s.userAge ?? 30 },
                            set: { s.userAge = $0 }
                        )) {
                            ForEach(16..<80, id: \.self) { age in
                                Text("\(age)").tag(age)
                            }
                        }

                        Picker("Weight", selection: Binding(
                            get: { Int(s.bodyWeightLbs ?? 176) },
                            set: { s.bodyWeightLbs = Double($0) }
                        )) {
                            ForEach(Array(stride(from: 90, through: 350, by: 5)), id: \.self) { w in
                                Text("\(w) lbs").tag(w)
                            }
                        }

                        Picker("Sex", selection: Binding(
                            get: { s.isMale ?? true },
                            set: { s.isMale = $0 }
                        )) {
                            Text("Male").tag(true)
                            Text("Female").tag(false)
                        }
                    }

                    Section("Warmup Sets") {
                        ForEach(Array(s.effectiveWarmupPercentages.indices), id: \.self) { i in
                            HStack {
                                Text("Set \(i + 1)")
                                    .frame(width: 44, alignment: .leading)
                                Spacer()
                                Text("\(Int(s.effectiveWarmupPercentages[i] * 100))%")
                                    .monospacedDigit()
                                Text("×")
                                Text("\(s.effectiveWarmupReps[i]) reps")
                                    .monospacedDigit()

                                Button(role: .destructive) {
                                    s.effectiveWarmupPercentages.remove(at: i)
                                    s.effectiveWarmupReps.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Menu {
                            ForEach([20, 30, 40, 50, 60, 70], id: \.self) { pct in
                                Menu("\(pct)%") {
                                    ForEach([3, 5, 8, 10], id: \.self) { reps in
                                        Button("\(pct)% × \(reps) reps") {
                                            s.effectiveWarmupPercentages.append(Double(pct) / 100.0)
                                            s.effectiveWarmupReps.append(reps)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Add Warmup Set", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Program") {
                    if let cycle = currentCycle {
                        HStack {
                            Text("Current Cycle")
                            Spacer()
                            Text("\(cycle.number)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Variant")
                            Spacer()
                            Text(cycle.programVariant.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Edit Training Maxes") {
                        showingTMSetup = true
                    }

                    Button("Start New Cycle") {
                        showingNewCycleSheet = true
                    }
                }

                Section("Data") {
                    Button("Import from Strong App") {
                        showingImport = true
                    }
                    Button("Backup & Restore") {
                        showingBackup = true
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingTMSetup) {
                TrainingMaxSetupView()
            }
            .sheet(isPresented: $showingImport) {
                StrongImportView()
            }
            .sheet(isPresented: $showingBackup) {
                BackupRestoreView()
            }
            .sheet(isPresented: $showingNewCycleSheet) {
                if let cycle = currentCycle {
                    NewCycleSheet(cycle: cycle) { increments in
                        startNewCycle(increments: increments)
                    }
                    .presentationDetents([.medium])
                }
            }
        }
    }

    private func startNewCycle(increments: [Lift: Double]) {
        guard let current = currentCycle else { return }
        current.isComplete = true
        var newMaxes: [String: Double] = [:]
        for lift in Lift.allCases {
            let currentTM = current.trainingMax(for: lift)
            newMaxes[lift.rawValue] = currentTM + (increments[lift] ?? lift.progressionIncrement)
        }
        let next = Cycle(
            number: current.number + 1,
            startDate: .now,
            trainingMaxes: newMaxes,
            variant: current.programVariant
        )
        modelContext.insert(next)
    }

    private func restLabel(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}

// MARK: - New Cycle Sheet

struct NewCycleSheet: View {
    let cycle: Cycle
    let onStart: ([Lift: Double]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var increments: [Lift: Double] = [:]

    private static let incrementOptions: [Double] = [0, 2.5, 5, 10, 15, 20]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cycle \(cycle.number) → \(cycle.number + 1)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)

                Section("TM Increases") {
                    ForEach(Lift.allCases) { lift in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(lift.displayName)
                                Text("\(Int(cycle.trainingMax(for: lift))) → \(Int(cycle.trainingMax(for: lift) + increment(for: lift))) lbs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { increment(for: lift) },
                                set: { increments[lift] = $0 }
                            )) {
                                ForEach(Self.incrementOptions, id: \.self) { inc in
                                    Text("+\(formatWeight(inc))").tag(inc)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .navigationTitle("New Cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(increments)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func increment(for lift: Lift) -> Double {
        increments[lift] ?? lift.progressionIncrement
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}
