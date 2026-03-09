import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingRestoreConfirm = false
    @State private var pendingRestoreURL: URL?
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var backupData: Data?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Back up your data to a JSON file, or restore from a previous backup.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Spacer()

                if let status = statusMessage {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(isError ? .red : .green)
                        .multilineTextAlignment(.center)
                }

                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingImporter = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: JSONBackupDocument(data: backupData ?? Data()),
                contentType: .json,
                defaultFilename: BackupManager.backupFilename()
            ) { result in
                switch result {
                case .success:
                    statusMessage = "Backup saved successfully."
                    isError = false
                case .failure(let error):
                    statusMessage = "Export failed: \(error.localizedDescription)"
                    isError = true
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleRestoreFileSelection(result)
            }
            .alert("Restore Backup?", isPresented: $showingRestoreConfirm) {
                Button("Restore", role: .destructive) {
                    performRestore()
                }
                Button("Cancel", role: .cancel) {
                    pendingRestoreURL = nil
                }
            } message: {
                Text("This will replace ALL current data with the backup. This cannot be undone.")
            }
        }
    }

    private func exportBackup() {
        do {
            backupData = try BackupManager.exportData(from: modelContext)
            showingExporter = true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func handleRestoreFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            pendingRestoreURL = url
            showingRestoreConfirm = true
        case .failure(let error):
            statusMessage = "File selection failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func performRestore() {
        guard let url = pendingRestoreURL else { return }
        defer { pendingRestoreURL = nil }

        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "Unable to access the selected file."
            isError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let result = try BackupManager.restoreData(from: data, context: modelContext)
            statusMessage = "Restored \(result.workouts) workouts, \(result.cycles) cycles, \(result.exercises) exercises."
            isError = false
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
            isError = true
        }
    }
}

// MARK: - FileDocument wrapper for export

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
