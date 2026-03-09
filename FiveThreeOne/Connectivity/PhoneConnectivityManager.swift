import Foundation
import WatchConnectivity

/// Phone-side WatchConnectivity manager. Sends rest timer and workout state to the watch.
@MainActor @Observable
final class PhoneConnectivityManager: NSObject {
    var isWatchReachable = false

    // Watch-initiated actions (observed by TemplateWorkoutView)
    var watchRequestedCompleteSet = false
    var watchRequestedStopTimer = false

    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func sendTimerStarted(totalSeconds: Int, recoveryHR: Int?) {
        send([
            "type": "timerStart",
            "totalSeconds": totalSeconds,
            "recoveryHR": recoveryHR ?? 0
        ])
    }

    func sendTimerStopped() {
        send(["type": "timerStop"])
    }

    func sendWorkoutStarted() {
        send(["type": "workoutStart"])
    }

    func sendWorkoutFinished() {
        send(["type": "workoutFinish"])
    }

    func sendSetCompleted(exerciseName: String, setNumber: Int, totalSets: Int, weight: Double, reps: Int, setType: String) {
        send([
            "type": "setComplete",
            "exerciseName": exerciseName,
            "setNumber": setNumber,
            "totalSets": totalSets,
            "weight": weight,
            "reps": reps,
            "setType": setType
        ])
    }

    func sendCurrentExercise(name: String, setNumber: Int, totalSets: Int, weight: Double, targetReps: Int, isAMRAP: Bool, setType: String) {
        send([
            "type": "currentSet",
            "exerciseName": name,
            "setNumber": setNumber,
            "totalSets": totalSets,
            "weight": weight,
            "targetReps": targetReps,
            "isAMRAP": isAMRAP,
            "setType": setType
        ])
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { error in
            print("WC send error: \(error.localizedDescription)")
        }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            isWatchReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isWatchReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = message["type"] as? String
        Task { @MainActor in
            switch type {
            case "completeSet":
                self.watchRequestedCompleteSet = true
            case "stopTimer":
                self.watchRequestedStopTimer = true
            default:
                break
            }
        }
    }
}
