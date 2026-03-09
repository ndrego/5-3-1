import SwiftUI
import SwiftData

struct TrainingMaxSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var isOnboarding: Bool = false

    @State private var liftInputs: [Lift: String] = [
        .squat: "", .bench: "", .deadlift: "", .overheadPress: ""
    ]
    @State private var liftTMPercents: [Lift: Double] = [
        .squat: 90, .bench: 90, .deadlift: 90, .overheadPress: 90
    ]
    @State private var selectedVariant: ProgramVariant = .standard
    @State private var useOneRepMax = true
    @State private var useSamePercent = true
    @State private var globalPercent: Double = 90

    var body: some View {
        NavigationStack {
            Form {
                inputMethodSection
                liftsSection
                if useOneRepMax {
                    tmPercentSection
                    calculatedTMSection
                }
                variantSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isOnboarding ? "Welcome to 531" : "Training Maxes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var inputMethodSection: some View {
        Section {
            Picker("Input Method", selection: $useOneRepMax) {
                Text("Enter 1RM").tag(true)
                Text("Enter TM directly").tag(false)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(useOneRepMax ? "Enter your 1 Rep Max" : "Enter your Training Max")
        }
    }

    private var liftsSection: some View {
        Section("Lifts (lbs)") {
            ForEach(Lift.allCases) { lift in
                liftField(lift.displayName, value: binding(for: lift))
            }
        }
    }

    private var tmPercentSection: some View {
        Section("TM Percentage") {
            Toggle("Same % for all lifts", isOn: $useSamePercent)
                .onChange(of: useSamePercent) { _, newValue in
                    if newValue {
                        for lift in Lift.allCases {
                            liftTMPercents[lift] = globalPercent
                        }
                    }
                }

            if useSamePercent {
                percentRow(label: "All Lifts", value: $globalPercent)
                    .onChange(of: globalPercent) { _, newValue in
                        for lift in Lift.allCases {
                            liftTMPercents[lift] = newValue
                        }
                    }
            } else {
                ForEach(Lift.allCases) { lift in
                    percentRow(
                        label: lift.shortName,
                        value: Binding(
                            get: { liftTMPercents[lift] ?? 90 },
                            set: { liftTMPercents[lift] = $0 }
                        )
                    )
                }
            }
        }
    }

    private var calculatedTMSection: some View {
        Section("Calculated Training Maxes") {
            ForEach(Lift.allCases) { lift in
                HStack {
                    Text(lift.displayName)
                    Spacer()
                    if let value = Double(liftInputs[lift] ?? "") {
                        let pct = liftTMPercents[lift] ?? 90
                        let tm = roundToFive(value * pct / 100.0)
                        Text("\(Int(tm)) lbs")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("(\(Int(pct))%)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var variantSection: some View {
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

    // MARK: - Components

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

    private func percentRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 60, alignment: .leading)
            Slider(value: value, in: 80...95, step: 5)
            Text("\(Int(value.wrappedValue))%")
                .monospacedDigit()
                .frame(width: 40)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func binding(for lift: Lift) -> Binding<String> {
        Binding(
            get: { liftInputs[lift] ?? "" },
            set: { liftInputs[lift] = $0 }
        )
    }

    private var isValid: Bool {
        Lift.allCases.allSatisfy { lift in
            guard let val = Double(liftInputs[lift] ?? "") else { return false }
            return val > 0
        }
    }

    private func save() {
        var trainingMaxes: [String: Double] = [:]
        var tmPercentages: [String: Double] = [:]

        for lift in Lift.allCases {
            let input = Double(liftInputs[lift] ?? "0") ?? 0
            let pct = liftTMPercents[lift] ?? 90
            let multiplier = useOneRepMax ? pct / 100.0 : 1.0
            trainingMaxes[lift.rawValue] = roundToFive(input * multiplier)
            tmPercentages[lift.rawValue] = pct / 100.0
        }

        let cycle = Cycle(
            number: 1,
            trainingMaxes: trainingMaxes,
            variant: selectedVariant
        )
        modelContext.insert(cycle)

        if isOnboarding {
            let settings = UserSettings(trainingMaxPercentages: tmPercentages)
            modelContext.insert(settings)
            Exercise.seedDefaults(in: modelContext)
        }

        dismiss()
    }

    private func roundToFive(_ value: Double) -> Double {
        (value / 5.0).rounded() * 5.0
    }
}
