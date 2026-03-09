import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]
    @Query(sort: \Cycle.number, order: .reverse) private var cycles: [Cycle]

    @State private var showingTMSetup = false
    @State private var showingImport = false
    @State private var showingNewCycleConfirm = false

    private var userSettings: UserSettings? { settings.first }
    private var currentCycle: Cycle? { cycles.first(where: { !$0.isComplete }) ?? cycles.first }

    var body: some View {
        NavigationStack {
            Form {
                if let s = userSettings {
                    Section("Equipment") {
                        HStack {
                            Text("Bar Weight")
                            Spacer()
                            Text("\(Int(s.barWeight)) lbs")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Round To")
                            Spacer()
                            Text("\(Int(s.roundTo)) lbs")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Available Plates")
                            Spacer()
                            Text(s.availablePlates.map { formatWeight($0) }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Rest Timers") {
                        HStack {
                            Text("Main Sets")
                            Spacer()
                            Text("\(s.defaultRestSeconds / 60):\(String(format: "%02d", s.defaultRestSeconds % 60))")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Supplemental")
                            Spacer()
                            Text("\(s.supplementalRestSeconds / 60):\(String(format: "%02d", s.supplementalRestSeconds % 60))")
                                .foregroundStyle(.secondary)
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

                    Button("Start New Cycle (+5/+10)") {
                        showingNewCycleConfirm = true
                    }
                }

                Section("Data") {
                    Button("Import from Strong App") {
                        showingImport = true
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
            .confirmationDialog("Start New Cycle?", isPresented: $showingNewCycleConfirm) {
                Button("Start New Cycle") {
                    startNewCycle()
                }
            } message: {
                if let cycle = currentCycle {
                    Text("This will increase your training maxes (+5 upper, +10 lower) and start Cycle \(cycle.number + 1).")
                }
            }
        }
    }

    private func startNewCycle() {
        guard let current = currentCycle else { return }
        current.isComplete = true
        let next = current.nextCycle()
        modelContext.insert(next)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}
