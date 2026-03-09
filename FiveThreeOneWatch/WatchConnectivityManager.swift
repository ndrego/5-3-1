import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity manager. Receives rest timer and workout state from the phone.
@MainActor @Observable
final class WatchConnectivityManager: NSObject {
    var isPhoneReachable = false
    var workoutManager: WatchWorkoutManager?
    var repCountingManager: RepCountingManager?
    var repCountingEnabled = false

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

    func sendRepCount(_ count: Int) {
        send(["type": "repCount", "repCount": count])
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
        let enabled = message["enabled"] as? Bool
        let sensitivity = message["sensitivity"] as? [String: Double]
        let tempo = message["tempo"] as? [String: Double]

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
                setType: setType,
                enabled: enabled,
                sensitivity: sensitivity,
                tempo: tempo
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
        setType: String?,
        enabled: Bool?,
        sensitivity: [String: Double]?,
        tempo: [String: Double]?
    ) {
        guard let type else { return }

        switch type {
        case "timerStart":
            let total = totalSeconds ?? 180
            let effectiveRecovery = (recoveryHR == nil || recoveryHR == 0) ? nil : recoveryHR
            workoutManager?.startTimer(seconds: total, recoveryHR: effectiveRecovery)
            // Stop rep counting during rest
            _ = repCountingManager?.stopCounting()

        case "timerStop":
            workoutManager?.stopTimer()

        case "workoutStart":
            workoutManager?.workoutActive = true

        case "workoutFinish":
            workoutManager?.workoutActive = false
            workoutManager?.stopTimer()
            _ = repCountingManager?.stopCounting()

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
            // Start rep counting for this set
            if repCountingEnabled, let name = exerciseName {
                repCountingManager?.onRepCounted = { [weak self] count in
                    self?.sendRepCount(count)
                }
                repCountingManager?.startCounting(exerciseName: name)
            }

        case "setComplete":
            workoutManager?.markSetCompleted(
                exercise: exerciseName ?? "",
                setNumber: setNumber ?? 0,
                totalSets: totalSets ?? 0,
                weight: weight ?? 0,
                reps: reps ?? 0,
                setType: setType ?? "main"
            )
            _ = repCountingManager?.stopCounting()

        case "repCountingEnabled":
            repCountingEnabled = enabled ?? false

        case "repTuning":
            if let sensitivity {
                repCountingManager?.sensitivityOverrides = sensitivity
            }
            if let tempo {
                repCountingManager?.tempoOverrides = tempo
            }

        default:
            break
        }
    }
}
