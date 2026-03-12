import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]

    var body: some View {
        if settings.isEmpty {
            TrainingMaxSetupView(isOnboarding: true)
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    private var connectivity: PhoneConnectivityManager { .shared }

    var body: some View {
        TabView {
            TemplateListView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            DashboardView()
                .tabItem {
                    Label("Program", systemImage: "calendar")
                }

            HistoryListView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            connectivity.activate()
            connectivity.clearWorkoutState()
            Exercise.seedDefaults(in: modelContext)
        }
    }
}
