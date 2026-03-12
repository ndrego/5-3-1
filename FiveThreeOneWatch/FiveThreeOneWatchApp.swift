import SwiftUI

@main
struct FiveThreeOneWatchApp: App {
    @State private var connectivityManager = WatchConnectivityManager()
    @State private var workoutManager = WatchWorkoutManager()
    @State private var repCountingManager = RepCountingManager()

    var body: some Scene {
        WindowGroup {
            WatchHomeView(
                connectivity: connectivityManager,
                workoutManager: workoutManager,
                repCountingManager: repCountingManager
            )
            .onAppear {
                connectivityManager.activate()
                connectivityManager.workoutManager = workoutManager
                connectivityManager.repCountingManager = repCountingManager
                repCountingManager.requestMotionAuthorization()
            }
        }
    }
}
