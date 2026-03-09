import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StrongImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var importResult: StrongImporter.ImportResult?
    @State private var addedExercises: [String] = []
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let result = importResult {
                    resultView(result)
                } else {
                    instructionsView
                }
            }
            .padding()
            .navigationTitle("Import from Strong")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private var instructionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Import your workout history from the Strong app.")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("How to export from Strong:")
                    .font(.headline)
                Text("1. Open Strong app")
                Text("2. Go to Settings")
                Text("3. Tap \"Export Strong Data\"")
                Text("4. Save the CSV file")
                Text("5. Import it here")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                showingFilePicker = true
            } label: {
                Text("Select CSV File")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)
        }
    }

    @ViewBuilder
    private func resultView(_ result: StrongImporter.ImportResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Import Complete")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)

                LabeledContent("Workouts Imported", value: "\(result.workoutsImported)")
                LabeledContent("Sets Imported", value: "\(result.setsImported)")
                LabeledContent("Exercises Found", value: "\(result.exercisesFound.count)")

                if !result.unmappedExercises.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exercises not mapped to main lifts:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(result.unmappedExercises.sorted()), id: \.self) { name in
                                Text("• \(name)")
                                    .font(.caption)
                            }
                        }
                    }
                }

                if !addedExercises.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Added to exercise library:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(addedExercises, id: \.self) { name in
                            Text("• \(name)")
                                .font(.caption)
                        }
                    }
                }

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warnings:")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        ForEach(result.errors, id: \.self) { error in
                            Text("• \(error)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let csvString = try String(contentsOf: url, encoding: .utf8)
                isImporting = true

                let importRes = StrongImporter.importCSV(csvString, context: modelContext)
                let added = StrongImporter.importAccessoryExercises(csvString, context: modelContext)

                importResult = importRes
                addedExercises = added
                isImporting = false
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }
}
