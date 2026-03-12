import Foundation
import WatchConnectivity

/// Phone-side WatchConnectivity manager. Sends rest timer and workout state to the watch.
@MainActor @Observable
final class PhoneConnectivityManager: NSObject {
    static let shared = PhoneConnectivityManager()

    var isWatchReachable = false

    // Watch-initiated actions (observed by TemplateWorkoutView)
    var watchRequestedCompleteSet = false
    var watchRequestedStopTimer = false
    var watchReportedRepCount: Int?
    var watchHeartRate: Double = 0
    var watchHeartRateUpdateCount: Int = 0

    // Calibration data received from watch
    var calibrationProfileKey: String?
    var calibrationMagnitudes: [Double]?
    var calibrationTimestamps: [Double]?
    var calibrationDataReceivedCount: Int = 0

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

    func sendTimerAdjusted(remainingSeconds: Int, totalSeconds: Int) {
        send([
            "type": "timerAdjust",
            "remainingSeconds": remainingSeconds,
            "totalSeconds": totalSeconds
        ])
    }

    func sendWorkoutStarted() {
        send(["type": "workoutStart"])
        updateContext(["workoutActive": true])
    }

    func clearWorkoutState() {
        updateContext(["workoutActive": false])
    }

    func sendRepCountingEnabled(_ enabled: Bool) {
        send(["type": "repCountingEnabled", "enabled": enabled])
    }

    func sendRepTuning(sensitivity: [String: Double], tempo: [String: Double]) {
        send(["type": "repTuning", "sensitivity": sensitivity, "tempo": tempo])
    }

    func sendCalibrate(profileKey: String) {
        send(["type": "calibrate", "profileKey": profileKey])
    }

    func sendWorkoutFinished() {
        send(["type": "workoutFinish"])
        updateContext(["workoutActive": false])
        // Also use transferUserInfo as guaranteed delivery in case sendMessage was dropped
        session?.transferUserInfo(["type": "workoutFinish"])
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

    func sendCurrentExercise(name: String, setNumber: Int, totalSets: Int, weight: Double, targetReps: Int, isAMRAP: Bool, setType: String, repCountingEnabled: Bool = false) {
        send([
            "type": "currentSet",
            "exerciseName": name,
            "setNumber": setNumber,
            "totalSets": totalSets,
            "weight": weight,
            "targetReps": targetReps,
            "isAMRAP": isAMRAP,
            "setType": setType,
            "repCountingEnabled": repCountingEnabled
        ])
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.isReachable else {
            print("WC not reachable, message dropped: \(message["type"] as? String ?? "unknown")")
            return
        }
        session.sendMessage(message, replyHandler: nil) { error in
            print("WC send error: \(error.localizedDescription)")
        }
    }

    private func updateContext(_ context: [String: Any]) {
        guard let session else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("WC context update error: \(error.localizedDescription)")
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
        let repCount = message["repCount"] as? Int
        let bpm = message["bpm"] as? Double
        let profileKey = message["profileKey"] as? String
        let magnitudes = message["magnitudes"] as? [Double]
        let timestamps = message["timestamps"] as? [Double]
        Task { @MainActor in
            switch type {
            case "completeSet":
                self.watchRequestedCompleteSet = true
            case "stopTimer":
                self.watchRequestedStopTimer = true
            case "repCount":
                self.watchReportedRepCount = repCount
            case "heartRate":
                if let bpm {
                    self.watchHeartRate = bpm
                    self.watchHeartRateUpdateCount += 1
                }
            case "calibrationData":
                self.calibrationProfileKey = profileKey
                self.calibrationMagnitudes = magnitudes
                self.calibrationTimestamps = timestamps
                self.calibrationDataReceivedCount += 1
            default:
                break
            }
        }
    }
}
