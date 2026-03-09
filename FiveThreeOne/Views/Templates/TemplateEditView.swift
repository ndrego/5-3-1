import SwiftUI
import SwiftData

struct TemplateEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    let template: WorkoutTemplate?

    @State private var name: String = ""
    @State private var entries: [TemplateExerciseEntry] = []
    @State private var showingExercisePicker = false
    @State private var supersetLinkingIndex: Int?

    private var isNew: Bool { template == nil }

    private var nextSupersetGroup: Int {
        (entries.compactMap { $0.supersetGroup }.max() ?? 0) + 1
    }

    private static let supersetColors: [Color] = [.purple, .teal, .pink, .indigo, .mint]

    private func supersetColor(for group: Int) -> Color {
        Self.supersetColors[(group - 1) % Self.supersetColors.count]
    }

    var body: some View {
        List {
            Section("Template Name") {
                TextField("e.g. Deadlift + Bench", text: $name)
            }

            Section("Exercises") {
                if entries.isEmpty {
                    Text("No exercises added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entries.indices), id: \.self) { index in
                        HStack(spacing: 12) {
                            // Superset color bar
                            if let group = entries[index].supersetGroup {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(supersetColor(for: group))
                                    .frame(width: 4, height: 36)
                            }

                            // Move buttons
                            VStack(spacing: 0) {
                                Button {
                                    guard index > 0 else { return }
                                    entries.swapAt(index, index - 1)
                                    reindex()
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption)
                                        .foregroundStyle(index > 0 ? .primary : .quaternary)
                                }
                                .disabled(index == 0)

                                Button {
                                    guard index < entries.count - 1 else { return }
                                    entries.swapAt(index, index + 1)
                                    reindex()
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(index < entries.count - 1 ? .primary : .quaternary)
                                }
                                .disabled(index == entries.count - 1)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading) {
                                Text(entries[index].exerciseName)
                                    .font(.body)
                                HStack(spacing: 4) {
                                    if entries[index].isMainLift {
                                        Text("5/3/1 Main Lift")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                    if let group = entries[index].supersetGroup {
                                        Text("Superset \(group)")
                                            .font(.caption)
                                            .foregroundStyle(supersetColor(for: group))
                                    }
                                }
                            }

                            Spacer()

                            // Superset link/unlink
                            if let group = entries[index].supersetGroup {
                                Button {
                                    entries[index].supersetGroup = nil
                                    // If only one remains in group, unlink it too
                                    let remaining = entries.indices.filter { entries[$0].supersetGroup == group }
                                    if remaining.count == 1 {
                                        entries[remaining[0]].supersetGroup = nil
                                    }
                                } label: {
                                    Image(systemName: "link.badge.plus")
                                        .font(.caption)
                                        .foregroundStyle(supersetColor(for: group))
                                }
                                .buttonStyle(.plain)
                            } else if supersetLinkingIndex == index {
                                Button {
                                    supersetLinkingIndex = nil
                                } label: {
                                    Text("Cancel")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else if let sourceIdx = supersetLinkingIndex {
                                Button {
                                    let group = entries[sourceIdx].supersetGroup ?? nextSupersetGroup
                                    entries[sourceIdx].supersetGroup = group
                                    entries[index].supersetGroup = group
                                    supersetLinkingIndex = nil
                                } label: {
                                    Image(systemName: "link")
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    supersetLinkingIndex = index
                                } label: {
                                    Image(systemName: "link")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                entries.remove(at: index)
                                supersetLinkingIndex = nil
                                reindex()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isNew ? "New Template" : "Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(name.isEmpty || entries.isEmpty)
            }
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExercisePickerView(entries: $entries)
            }
        }
        .onAppear {
            if let template {
                name = template.name
                entries = template.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })
            }
        }
    }

    private func reindex() {
        for i in entries.indices {
            entries[i].sortOrder = i
        }
    }

    private func save() {
        reindex()
        if let template {
            template.name = name
            template.exerciseEntries = entries
        } else {
            let newTemplate = WorkoutTemplate(
                name: name,
                sortOrder: 0,
                exerciseEntries: entries
            )
            modelContext.insert(newTemplate)
        }
        dismiss()
    }
}

// MARK: - Exercise Picker

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Binding var entries: [TemplateExerciseEntry]

    @State private var searchText = ""

    var body: some View {
        List {
            Section("Main Lifts (5/3/1)") {
                ForEach(Lift.allCases) { lift in
                    let alreadyAdded = entries.contains(where: { $0.mainLift == lift.rawValue })
                    Button {
                        guard !alreadyAdded else { return }
                        entries.append(TemplateExerciseEntry(
                            exerciseName: lift.displayName,
                            mainLift: lift.rawValue,
                            sortOrder: entries.count
                        ))
                        dismiss()
                    } label: {
                        HStack {
                            Text(lift.displayName)
                            Spacer()
                            if alreadyAdded {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(alreadyAdded)
                }
            }

            Section("Accessories") {
                ForEach(filteredExercises) { exercise in
                    let alreadyAdded = entries.contains(where: { $0.exerciseName == exercise.name })
                    Button {
                        guard !alreadyAdded else { return }
                        entries.append(TemplateExerciseEntry(
                            exerciseName: exercise.name,
                            sortOrder: entries.count
                        ))
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.name)
                                Text(exercise.exerciseCategory.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if alreadyAdded {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(alreadyAdded)
                }
            }
        }
        .navigationTitle("Add Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
