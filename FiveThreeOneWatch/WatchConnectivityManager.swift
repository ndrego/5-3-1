import Foundation
import WatchConnectivity

/// Watch-side WatchConnectivity manager. Receives rest timer and workout state from the phone.
/// Separated from NSObject/WCSessionDelegate to avoid @MainActor @Observable + delegate dispatch crashes.
@MainActor @Observable
final class WatchConnectivityManager {
    var isPhoneReachable = false
    var workoutManager: WatchWorkoutManager?
    var repCountingManager: RepCountingManager?
    var repCountingEnabled = false
    private var currentExerciseName: String?

    private var delegateHelper: WCSessionDelegateHelper?

    func activate() {
        guard WCSession.isSupported() else { return }
        let helper = WCSessionDelegateHelper(manager: self)
        self.delegateHelper = helper
        let session = WCSession.default
        session.delegate = helper
        session.activate()
    }

    func sendCompleteSet() {
        delegateHelper?.send(["type": "completeSet"])
    }

    func sendStopTimer() {
        delegateHelper?.send(["type": "stopTimer"])
    }

    func sendRepCount(_ count: Int) {
        delegateHelper?.send(["type": "repCount", "repCount": count])
    }

    func sendHeartRate(_ bpm: Double) {
        delegateHelper?.send(["type": "heartRate", "bpm": bpm])
    }

    func sendCalibrationData(profileKey: String, magnitudes: [Double], timestamps: [Double]) {
        delegateHelper?.send([
            "type": "calibrationData",
            "profileKey": profileKey,
            "magnitudes": magnitudes,
            "timestamps": timestamps
        ])
    }

    func handleCalibrate(profileKey: String) {
        print("[WC] Starting calibration for profile: \(profileKey)")
        repCountingManager?.onCalibrationSamples = { [weak self] magnitudes, timestamps in
            self?.sendCalibrationData(profileKey: profileKey, magnitudes: magnitudes, timestamps: timestamps)
        }
        repCountingManager?.startCalibration()
    }

    // MARK: - Message Handling (called from delegate helper on MainActor)

    func handleMessage(
        type: String,
        totalSeconds: Int?,
        remainingSeconds: Int?,
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
        print("[WC] handleMessage type=\(type)")
        switch type {
        case "timerStart":
            let total = totalSeconds ?? 180
            let effectiveRecovery = (recoveryHR == nil || recoveryHR == 0) ? nil : recoveryHR
            workoutManager?.startTimer(seconds: total, recoveryHR: effectiveRecovery)
            _ = repCountingManager?.stopCounting()

        case "timerStop":
            workoutManager?.stopTimer()
            // Restart rep counting after rest
            if repCountingEnabled, let name = currentExerciseName {
                startRepCounting(exerciseName: name)
            }

        case "timerCompleted":
            workoutManager?.timerCompletedFromPhone()
            // Restart rep counting after rest
            if repCountingEnabled, let name = currentExerciseName {
                startRepCounting(exerciseName: name)
            }

        case "timerAdjust":
            if let remaining = remainingSeconds, let total = totalSeconds {
                workoutManager?.adjustTimer(remaining: remaining, total: total)
            }

        case "workoutStart":
            startWorkout()

        case "workoutFinish":
            // Handled above in delegate helper with effort score
            break

        case "currentSet":
            currentExerciseName = exerciseName
            workoutManager?.updateCurrentSet(
                exercise: exerciseName ?? "",
                setNumber: setNumber ?? 0,
                totalSets: totalSets ?? 0,
                weight: weight ?? 0,
                targetReps: targetReps ?? 0,
                isAMRAP: isAMRAP ?? false,
                setType: setType ?? "main"
            )
            // Start rep counting — isActive on RepCountingManager gates whether
            // reps are actually reported. timerStart sets isActive=false via stopCounting(),
            // and the next currentSet (after rest) sets isActive=true via startCounting().
            if repCountingEnabled, let name = exerciseName {
                startRepCounting(exerciseName: name)
                print("[WC] currentSet: started rep counting for \(name), isActive=\(repCountingManager?.isActive ?? false)")
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
            // Don't stopCounting here — timerStart handles that.
            // setComplete is also sent from sendWatchContext() for display updates.

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

    private func startRepCounting(exerciseName: String) {
        repCountingManager?.onRepCounted = { [weak self] count in
            self?.sendRepCount(count)
        }
        repCountingManager?.startCounting(exerciseName: exerciseName)
    }

    func startWorkout() {
        guard !(workoutManager?.workoutActive ?? false) else {
            print("[WC] startWorkout skipped — already active")
            return
        }
        print("[WC] startWorkout — setting up callbacks")
        workoutManager?.workoutActive = true
        workoutManager?.onHeartRateUpdate = { [weak self] bpm in
            self?.sendHeartRate(bpm)
        }
        workoutManager?.startWorkoutSession()
    }

    func stopWorkout(averageEffort: Double? = nil) {
        workoutManager?.workoutActive = false
        workoutManager?.stopTimer()
        workoutManager?.stopWorkoutSession(averageEffort: averageEffort)
        repCountingManager?.stopAccelerometer()
    }

    func handleReachabilityChanged(_ reachable: Bool) {
        isPhoneReachable = reachable
    }
}

// MARK: - WCSession Delegate Helper (non-MainActor, handles WCSession delegates)

/// Separate class to own WCSessionDelegate conformance,
/// avoiding conflicts between @MainActor @Observable and WCSession's background queue callbacks.
final class WCSessionDelegateHelper: NSObject, WCSessionDelegate, @unchecked Sendable {
    private weak var manager: WatchConnectivityManager?

    init(manager: WatchConnectivityManager) {
        self.manager = manager
    }

    func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { error in
            print("WC send error: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let workoutActive = session.receivedApplicationContext["workoutActive"] as? Bool ?? false
        Task { @MainActor [weak self] in
            self?.manager?.handleReachabilityChanged(reachable)
            if workoutActive {
                self?.manager?.startWorkout()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.manager?.handleReachabilityChanged(reachable)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let workoutActive = applicationContext["workoutActive"] as? Bool
        Task { @MainActor [weak self] in
            guard let workoutActive else { return }
            if workoutActive {
                self?.manager?.startWorkout()
            } else {
                self?.manager?.stopWorkout()
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = message["type"] as? String
        let totalSeconds = message["totalSeconds"] as? Int
        let remainingSeconds = message["remainingSeconds"] as? Int
        let recoveryHR = message["recoveryHR"] as? Int
        let exerciseName = message["exerciseName"] as? String
        let setNumber = message["setNumber"] as? Int
        let totalSets = message["totalSets"] as? Int
        let weight = message["weight"] as? Double
        let targetReps = message["targetReps"] as? Int
        let reps = message["reps"] as? Int
        let isAMRAP = message["isAMRAP"] as? Bool
        let setType = message["setType"] as? String
        let msgRepCountingEnabled = message["repCountingEnabled"] as? Bool
        let enabled = message["enabled"] as? Bool
        let sensitivity = message["sensitivity"] as? [String: Double]
        let tempo = message["tempo"] as? [String: Double]

        guard let type else { return }

        // Handle calibrate separately — needs its own profileKey field
        if type == "calibrate" {
            let profileKey = message["profileKey"] as? String ?? ""
            Task { @MainActor [weak self] in
                self?.manager?.handleCalibrate(profileKey: profileKey)
            }
            return
        }

        // Handle workoutFinish with effort score
        if type == "workoutFinish" {
            let averageEffort = message["averageEffort"] as? Double
            Task { @MainActor [weak self] in
                self?.manager?.stopWorkout(averageEffort: averageEffort)
                self?.manager?.repCountingManager?.stopAccelerometer()
            }
            return
        }

        Task { @MainActor [weak self] in
            // Update rep counting from currentSet message so it's set before handleMessage checks it
            if let msgRepCountingEnabled {
                self?.manager?.repCountingEnabled = msgRepCountingEnabled
            }
            self?.manager?.handleMessage(
                type: type,
                totalSeconds: totalSeconds,
                remainingSeconds: remainingSeconds,
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

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let type = userInfo["type"] as? String
        Task { @MainActor [weak self] in
            if type == "workoutFinish" {
                self?.manager?.stopWorkout()
            }
        }
    }
}
