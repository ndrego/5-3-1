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

    private var isNew: Bool { template == nil }

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
                                if entries[index].isMainLift {
                                    Text("5/3/1 Main Lift")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }

                            Spacer()

                            Button {
                                entries.remove(at: index)
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
