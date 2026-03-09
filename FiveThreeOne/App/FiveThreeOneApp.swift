import SwiftUI
import SwiftData

@main
struct FiveThreeOneApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Cycle.self,
            CompletedWorkout.self,
            UserSettings.self,
            Exercise.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
