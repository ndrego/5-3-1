import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity manager. Receives rest timer and workout state from the phone.
@MainActor @Observable
final class WatchConnectivityManager: NSObject {
    var isPhoneReachable = false
    var workoutManager: WatchWorkoutManager?

    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func sendCompleteSet() {
        send(["type": "completeSet"])
    }

    func sendStopTimer() {
        send(["type": "stopTimer"])
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { error in
            print("WC send error: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            isPhoneReachable = reachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isPhoneReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = message["type"] as? String
        let totalSeconds = message["totalSeconds"] as? Int
        let recoveryHR = message["recoveryHR"] as? Int
        let exerciseName = message["exerciseName"] as? String
        let setNumber = message["setNumber"] as? Int
        let totalSets = message["totalSets"] as? Int
        let weight = message["weight"] as? Double
        let targetReps = message["targetReps"] as? Int
        let reps = message["reps"] as? Int
        let isAMRAP = message["isAMRAP"] as? Bool
        let setType = message["setType"] as? String

        Task { @MainActor in
            self.handleMessage(
                type: type,
                totalSeconds: totalSeconds,
                recoveryHR: recoveryHR,
                exerciseName: exerciseName,
                setNumber: setNumber,
                totalSets: totalSets,
                weight: weight,
                targetReps: targetReps,
                reps: reps,
                isAMRAP: isAMRAP,
                setType: setType
            )
        }
    }

    @MainActor
    private func handleMessage(
        type: String?,
        totalSeconds: Int?,
        recoveryHR: Int?,
        exerciseName: String?,
        setNumber: Int?,
        totalSets: Int?,
        weight: Double?,
        targetReps: Int?,
        reps: Int?,
        isAMRAP: Bool?,
        setType: String?
    ) {
        guard let type else { return }

        switch type {
        case "timerStart":
            let total = totalSeconds ?? 180
            let effectiveRecovery = (recoveryHR == nil || recoveryHR == 0) ? nil : recoveryHR
            workoutManager?.startTimer(seconds: total, recoveryHR: effectiveRecovery)

        case "timerStop":
            workoutManager?.stopTimer()

        case "workoutStart":
            workoutManager?.workoutActive = true

        case "workoutFinish":
            workoutManager?.workoutActive = false
            workoutManager?.stopTimer()

        case "currentSet":
            workoutManager?.updateCurrentSet(
                exercise: exerciseName ?? "",
                setNumber: setNumber ?? 0,
                totalSets: totalSets ?? 0,
                weight: weight ?? 0,
                targetReps: targetReps ?? 0,
                isAMRAP: isAMRAP ?? false,
                setType: setType ?? "main"
            )

        case "setComplete":
            workoutManager?.markSetCompleted(
                exercise: exerciseName ?? "",
                setNumber: setNumber ?? 0,
                totalSets: totalSets ?? 0,
                weight: weight ?? 0,
                reps: reps ?? 0,
                setType: setType ?? "main"
            )

        default:
            break
        }
    }
}
