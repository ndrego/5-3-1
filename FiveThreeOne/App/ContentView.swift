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
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
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
    }
}
