import Foundation
import HealthKit
import WatchKit

/// Manages rest timer, HR monitoring via HKWorkoutSession, and haptics on the watch.
@MainActor @Observable
final class WatchWorkoutManager {
    var workoutActive = false
    var currentHR: Double = 0
    var timerRunning = false
    var timerRemaining: Int = 0
    var timerTotal: Int = 0
    var recovered = false
    var recoveryTargetHR: Int?
    var onTimerCompleted: (() -> Void)?

    // Callback for sending HR to the phone
    var onHeartRateUpdate: ((Double) -> Void)?

    // Current exercise context
    var currentExercise: String = ""
    var currentSetNumber: Int = 0
    var currentTotalSets: Int = 0
    var currentWeight: Double = 0
    var currentTargetReps: Int = 0
    var currentIsAMRAP = false
    var currentSetType: String = "main"
    var setsCompleted: Int = 0

    private var sessionHelper: WorkoutSessionHelper?
    private var hrPollTask: Task<Void, Never>?
    private var restTimerTask: Task<Void, Never>?

    // MARK: - Heart Rate

    func requestHRAuthorization() async {
        #if DEBUG && targetEnvironment(simulator)
        startSimulation()
        return
        #else
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let healthStore = HKHealthStore()
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        do {
            try await healthStore.requestAuthorization(
                toShare: [HKWorkoutType.workoutType(), activeEnergy],
                read: [hrType, activeEnergy]
            )
        } catch {
            print("Watch HR authorization failed: \(error)")
        }
        #endif
    }

    /// Start an HKWorkoutSession to enable continuous heart rate streaming.
    func startWorkoutSession() {
        #if DEBUG && targetEnvironment(simulator)
        startSimulation()
        return
        #endif

        // If there's already a session running, stop it first
        if let existing = sessionHelper {
            existing.stop()
            sessionHelper = nil
        }

        let helper = WorkoutSessionHelper()
        self.sessionHelper = helper
        helper.start()
        startHRPolling()
    }

    /// Stop the HKWorkoutSession when the workout finishes.
    func stopWorkoutSession(averageEffort: Double? = nil) {
        hrPollTask?.cancel()
        hrPollTask = nil
        let helper = sessionHelper
        sessionHelper = nil
        currentHR = 0
        helper?.stop(averageEffort: averageEffort)
    }

    /// Poll the workout builder for latest HR every 2 seconds.
    private func startHRPolling() {
        hrPollTask?.cancel()
        hrPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let bpm = sessionHelper?.latestHeartRate() ?? 0
                if bpm > 0 {
                    currentHR = bpm
                    onHeartRateUpdate?(bpm)
                    checkRecovery()
                }
            }
        }
    }

    // MARK: - Rest Timer

    func startTimer(seconds: Int, recoveryHR: Int?) {
        stopTimer()
        timerTotal = seconds
        timerRemaining = seconds
        recoveryTargetHR = recoveryHR
        recovered = false
        timerRunning = true

        restTimerTask = Task {
            while !Task.isCancelled && timerRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                timerRemaining -= 1
            }
            if !Task.isCancelled && timerRemaining <= 0 {
                timerCompleted()
            }
        }
    }

    func adjustTimer(remaining: Int, total: Int) {
        timerTotal = total
        timerRemaining = remaining
    }

    func stopTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        timerRunning = false
        timerRemaining = 0
        recovered = false
        recoveryTargetHR = nil
    }

    private func timerCompleted() {
        print("[Timer] Timer completed, playing haptic")
        WKInterfaceDevice.current().play(.notification)
        stopTimer()
        onTimerCompleted?()
    }

    private func checkRecovery() {
        guard let target = recoveryTargetHR, !recovered, timerRunning else { return }
        if currentHR > 0 && currentHR <= Double(target) {
            recovered = true
            WKInterfaceDevice.current().play(.notification)
        }
    }

    // MARK: - Exercise Context

    func updateCurrentSet(exercise: String, setNumber: Int, totalSets: Int, weight: Double, targetReps: Int, isAMRAP: Bool, setType: String) {
        currentExercise = exercise
        currentSetNumber = setNumber
        currentTotalSets = totalSets
        currentWeight = weight
        currentTargetReps = targetReps
        currentIsAMRAP = isAMRAP
        currentSetType = setType
    }

    func markSetCompleted(exercise: String, setNumber: Int, totalSets: Int, weight: Double, reps: Int, setType: String) {
        currentExercise = exercise
        setsCompleted = setNumber
        currentTotalSets = totalSets
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Computed

    var timerProgress: Double {
        guard timerTotal > 0 else { return 0 }
        return Double(timerTotal - timerRemaining) / Double(timerTotal)
    }

    var formattedRemaining: String {
        let m = timerRemaining / 60
        let s = timerRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    var formattedWeight: String {
        if currentWeight == currentWeight.rounded() {
            return "\(Int(currentWeight))"
        }
        return String(format: "%.1f", currentWeight)
    }

    // MARK: - Simulation (DEBUG only)

    #if DEBUG
    private var simulationTask: Task<Void, Never>?

    private func startSimulation() {
        simulationTask?.cancel()
        simulationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let base: Double = timerRunning ? 130 : 85
                let noise = Double.random(in: -8...8)
                let bpm = base + noise
                currentHR = bpm
                onHeartRateUpdate?(bpm)
                checkRecovery()
            }
        }
    }
    #endif
}

// MARK: - Workout Session Helper (non-MainActor, handles HealthKit delegates)

/// Separate class to own the HKWorkoutSession and its delegates,
/// avoiding conflicts between @MainActor @Observable and HealthKit's threading.
final class WorkoutSessionHelper: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Latest HR value, updated from HealthKit delegate callbacks on their own queue.
    private var _latestHR: Double = 0
    private let hrLock = NSLock()

    /// Synchronous start — call from main thread. HealthKit on watchOS expects main thread.
    func start() {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: .now)
            builder.beginCollection(withStart: .now) { success, error in
                if let error {
                    print("Builder begin collection error: \(error)")
                }
            }
        } catch {
            print("Failed to start workout session: \(error)")
        }
    }

    /// Stop the workout, optionally saving an effort score (1-10 RPE mapped to Apple's 1-10 scale).
    func stop(averageEffort: Double? = nil) {
        guard let session, let builder else { return }
        session.end()

        // Save effort sample before finishing if available
        if let effort = averageEffort {
            addEffortSample(effort: effort, builder: builder)
        }

        builder.endCollection(withEnd: .now) { [weak self] success, error in
            self?.builder?.finishWorkout { workout, error in
                if let error {
                    print("Finish workout error: \(error)")
                }
            }
        }
        self.session = nil
        self.builder = nil
    }

    private func addEffortSample(effort: Double, builder: HKLiveWorkoutBuilder) {
        if #available(watchOS 11.0, *) {
            let type = HKQuantityType(.workoutEffortScore)
            let quantity = HKQuantity(unit: .appleEffortScore(), doubleValue: effort)
            let sample = HKQuantitySample(
                type: type,
                quantity: quantity,
                start: builder.startDate ?? .now,
                end: .now
            )
            builder.add([sample]) { success, error in
                if let error {
                    print("Failed to add effort sample: \(error)")
                } else {
                    print("[Workout] Saved effort score: \(String(format: "%.1f", effort))")
                }
            }
        } else {
            print("[Workout] Effort score requires watchOS 11+, skipping")
        }
    }

    /// Thread-safe read of the latest HR.
    func latestHeartRate() -> Double {
        hrLock.lock()
        let val = _latestHR
        hrLock.unlock()
        return val
    }

    // MARK: - HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        guard collectedTypes.contains(hrType) else { return }

        if let stats = workoutBuilder.statistics(for: hrType),
           let latest = stats.mostRecentQuantity() {
            let bpm = latest.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            hrLock.lock()
            _latestHR = bpm
            hrLock.unlock()
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    }
}
