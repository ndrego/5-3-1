import SwiftUI

@main
struct FiveThreeOneWatchApp: App {
    @State private var connectivityManager = WatchConnectivityManager()
    @State private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchHomeView(
                connectivity: connectivityManager,
                workoutManager: workoutManager
            )
            .onAppear {
                connectivityManager.activate()
                connectivityManager.workoutManager = workoutManager
            }
        }
    }
}
