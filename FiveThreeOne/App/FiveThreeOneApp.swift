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
            WorkoutTemplate.self,
        ])
        let isUITest = ProcessInfo.processInfo.arguments.contains("-UITests")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isUITest
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if isUITest {
                DemoDataSeeder.seed(in: container.mainContext)
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppearanceWrapper()
        }
        .modelContainer(sharedModelContainer)
    }
}

struct AppearanceWrapper: View {
    @Query private var settings: [UserSettings]

    private var colorScheme: ColorScheme? {
        switch settings.first?.appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil  // system default
        }
    }

    var body: some View {
        ContentView()
            .preferredColorScheme(colorScheme)
    }
}
