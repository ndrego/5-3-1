import SwiftUI
import SwiftData

struct TrainingMaxSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var isOnboarding: Bool = false

    @State private var squatTM: String = ""
    @State private var benchTM: String = ""
    @State private var deadliftTM: String = ""
    @State private var ohpTM: String = ""
    @State private var tmPercentage: Double = 90
    @State private var selectedVariant: ProgramVariant = .standard
    @State private var useOneRepMax = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Input Method", selection: $useOneRepMax) {
                        Text("Enter 1RM (auto-calculate TM)").tag(true)
                        Text("Enter Training Max directly").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if useOneRepMax {
                        HStack {
                            Text("TM Percentage")
                            Spacer()
                            Text("\(Int(tmPercentage))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $tmPercentage, in: 80...95, step: 5)
                    }
                } header: {
                    Text(useOneRepMax ? "Enter your 1 Rep Max" : "Enter your Training Max")
                }

                Section("Lifts (lbs)") {
                    liftField("Squat", value: $squatTM)
                    liftField("Bench Press", value: $benchTM)
                    liftField("Deadlift", value: $deadliftTM)
                    liftField("Overhead Press", value: $ohpTM)
                }

                if useOneRepMax {
                    Section("Calculated Training Maxes") {
                        tmPreview("Squat", input: squatTM)
                        tmPreview("Bench Press", input: benchTM)
                        tmPreview("Deadlift", input: deadliftTM)
                        tmPreview("OHP", input: ohpTM)
                    }
                }

                Section("Program Variant") {
                    Picker("Variant", selection: $selectedVariant) {
                        ForEach(ProgramVariant.allCases) { variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(selectedVariant.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isOnboarding ? "Welcome to 5/3/1" : "Training Maxes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private func liftField(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func tmPreview(_ label: String, input: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let value = Double(input) {
                let tm = roundToFive(value * tmPercentage / 100.0)
                Text("\(Int(tm)) lbs")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var isValid: Bool {
        [squatTM, benchTM, deadliftTM, ohpTM].allSatisfy { Double($0) != nil && Double($0)! > 0 }
    }

    private func save() {
        let multiplier = useOneRepMax ? tmPercentage / 100.0 : 1.0

        let trainingMaxes: [String: Double] = [
            Lift.squat.rawValue: roundToFive(Double(squatTM)! * multiplier),
            Lift.bench.rawValue: roundToFive(Double(benchTM)! * multiplier),
            Lift.deadlift.rawValue: roundToFive(Double(deadliftTM)! * multiplier),
            Lift.overheadPress.rawValue: roundToFive(Double(ohpTM)! * multiplier),
        ]

        let cycle = Cycle(
            number: 1,
            trainingMaxes: trainingMaxes,
            variant: selectedVariant
        )
        modelContext.insert(cycle)

        // Create settings if onboarding
        if isOnboarding {
            let settings = UserSettings(trainingMaxPercentage: tmPercentage / 100.0)
            modelContext.insert(settings)
            Exercise.seedDefaults(in: modelContext)
        }

        dismiss()
    }

    private func roundToFive(_ value: Double) -> Double {
        (value / 5.0).rounded() * 5.0
    }
}
