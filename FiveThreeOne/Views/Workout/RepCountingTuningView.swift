import SwiftUI
import SwiftData

struct RepCountingTuningView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [UserSettings]

    let onTuningChanged: (_ sensitivity: [String: Double], _ tempo: [String: Double]) -> Void

    private var userSettings: UserSettings? { settings.first }
    private let phoneConnectivity = PhoneConnectivityManager.shared

    @State private var calibratingKey: String?
    @State private var lastCalibratedKey: String?
    @State private var calibrationStatus: String?

    private struct ProfileTuning: Identifiable {
        let key: String
        let name: String
        let defaultThreshold: Double
        let defaultTempo: Double
        var id: String { key }
    }

    private let profiles: [ProfileTuning] = [
        .init(key: "squat", name: "Squat", defaultThreshold: 0.50, defaultTempo: 1.5),
        .init(key: "bench", name: "Bench", defaultThreshold: 0.40, defaultTempo: 1.2),
        .init(key: "deadlift", name: "Deadlift", defaultThreshold: 0.65, defaultTempo: 2.0),
        .init(key: "ohp", name: "OHP", defaultThreshold: 0.50, defaultTempo: 1.5),
        .init(key: "row", name: "Row", defaultThreshold: 0.45, defaultTempo: 1.2),
        .init(key: "curl", name: "Curl", defaultThreshold: 0.28, defaultTempo: 1.0),
        .init(key: "pullup", name: "Pull-up / Pulldown", defaultThreshold: 0.50, defaultTempo: 1.5),
        .init(key: "extension", name: "Extension / Pushdown", defaultThreshold: 0.25, defaultTempo: 0.8),
        .init(key: "raise", name: "Raise / Fly", defaultThreshold: 0.28, defaultTempo: 1.0),
        .init(key: "lunge", name: "Lunge / Split Squat", defaultThreshold: 0.50, defaultTempo: 1.5),
        .init(key: "core", name: "Core", defaultThreshold: 0.32, defaultTempo: 0.8),
        .init(key: "other", name: "Other", defaultThreshold: 0.40, defaultTempo: 1.0),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Adjust sensitivity and tempo per movement type. Changes apply immediately to the watch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(profiles) { profile in
                    Section(profile.name) {
                        let sens = sensitivity(for: profile.key)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Sensitivity")
                                Spacer()
                                Text(sensitivityLabel(sens))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: sensitivityBinding(for: profile.key),
                                in: 0.3...1.7,
                                step: 0.05
                            )
                        }

                        let tempo = tempo(for: profile.key, default: profile.defaultTempo)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Min Rep Time")
                                Spacer()
                                Text(String(format: "%.1fs", tempo))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: tempoBinding(for: profile.key, default: profile.defaultTempo),
                                in: 0.5...2.5,
                                step: 0.1
                            )
                        }

                        Button {
                            startCalibration(for: profile)
                        } label: {
                            HStack {
                                Label("Calibrate", systemImage: "waveform")
                                Spacer()
                                if calibratingKey == profile.key {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if lastCalibratedKey == profile.key, let calibrationStatus {
                                    Text(calibrationStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(calibratingKey != nil)
                    }
                }

                Section {
                    Button("Reset All to Defaults") {
                        userSettings?.repSensitivity = nil
                        userSettings?.repTempo = nil
                        sendTuning()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Rep Counter Tuning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: phoneConnectivity.calibrationDataReceivedCount) {
                processCalibrationData()
            }
        }
    }

    private func startCalibration(for profile: ProfileTuning) {
        calibratingKey = profile.key
        lastCalibratedKey = nil
        calibrationStatus = nil
        phoneConnectivity.sendCalibrate(profileKey: profile.key)
    }

    private func processCalibrationData() {
        guard let key = phoneConnectivity.calibrationProfileKey,
              let magnitudes = phoneConnectivity.calibrationMagnitudes,
              let timestamps = phoneConnectivity.calibrationTimestamps else { return }

        guard let profile = profiles.first(where: { $0.key == key }) else { return }

        if let result = CalibrationAnalyzer.analyze(
            magnitudes: magnitudes,
            timestamps: timestamps,
            baseThreshold: profile.defaultThreshold,
            baseTempo: profile.defaultTempo
        ) {
            if userSettings?.repSensitivity == nil {
                userSettings?.repSensitivity = [:]
            }
            if userSettings?.repTempo == nil {
                userSettings?.repTempo = [:]
            }
            userSettings?.repSensitivity?[key] = result.sensitivityMultiplier
            userSettings?.repTempo?[key] = result.tempo
            calibrationStatus = "\(result.peaksFound) reps detected"
            sendTuning()
        } else {
            calibrationStatus = "Could not detect reps"
        }

        lastCalibratedKey = key
        calibratingKey = nil

        // Clear received data
        phoneConnectivity.calibrationProfileKey = nil
        phoneConnectivity.calibrationMagnitudes = nil
        phoneConnectivity.calibrationTimestamps = nil
    }

    // MARK: - Helpers

    private func sensitivity(for key: String) -> Double {
        userSettings?.repSensitivity?[key] ?? 1.0
    }

    private func tempo(for key: String, default defaultVal: Double) -> Double {
        userSettings?.repTempo?[key] ?? defaultVal
    }

    private func sensitivityLabel(_ value: Double) -> String {
        if value < 0.6 { return "Very High" }
        if value < 0.85 { return "High" }
        if value < 1.15 { return "Normal" }
        if value < 1.6 { return "Low" }
        return "Very Low"
    }

    private func sensitivityBinding(for key: String) -> Binding<Double> {
        Binding(
            get: { sensitivity(for: key) },
            set: { newVal in
                if userSettings?.repSensitivity == nil {
                    userSettings?.repSensitivity = [:]
                }
                userSettings?.repSensitivity?[key] = newVal
                sendTuning()
            }
        )
    }

    private func tempoBinding(for key: String, default defaultVal: Double) -> Binding<Double> {
        Binding(
            get: { tempo(for: key, default: defaultVal) },
            set: { newVal in
                if userSettings?.repTempo == nil {
                    userSettings?.repTempo = [:]
                }
                userSettings?.repTempo?[key] = newVal
                sendTuning()
            }
        )
    }

    private func sendTuning() {
        let sens = userSettings?.repSensitivity ?? [:]
        let tempo = userSettings?.repTempo ?? [:]
        onTuningChanged(sens, tempo)
    }
}
