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
