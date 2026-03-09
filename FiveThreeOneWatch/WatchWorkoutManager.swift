import Foundation
import HealthKit
import WatchKit

/// Manages rest timer, HR monitoring, and haptics on the watch.
@MainActor @Observable
final class WatchWorkoutManager {
    var workoutActive = false
    var currentHR: Double = 0
    var timerRunning = false
    var timerRemaining: Int = 0
    var timerTotal: Int = 0
    var recovered = false
    var recoveryTargetHR: Int?

    // Current exercise context
    var currentExercise: String = ""
    var currentSetNumber: Int = 0
    var currentTotalSets: Int = 0
    var currentWeight: Double = 0
    var currentTargetReps: Int = 0
    var currentIsAMRAP = false
    var currentSetType: String = "main"
    var setsCompleted: Int = 0

    private let healthStore = HKHealthStore()
    private var hrQuery: HKAnchoredObjectQuery?
    private var timer: Timer?
    private var simulationTimer: Timer?

    // MARK: - Heart Rate

    func requestHRAuthorization() async {
        #if DEBUG && targetEnvironment(simulator)
        startSimulation()
        return
        #else
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [hrType])
            startHRMonitoring()
        } catch {}
        #endif
    }

    func startHRMonitoring() {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        stopHRMonitoring()

        let predicate = HKQuery.predicateForSamples(withStart: .now, end: nil, options: .strictStartDate)
        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.processSamples(samples)
            }
        }
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            Task { @MainActor in
                self?.processSamples(samples)
            }
        }
        healthStore.execute(query)
        hrQuery = query
    }

    func stopHRMonitoring() {
        if let query = hrQuery {
            healthStore.stop(query)
        }
        hrQuery = nil
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    private func processSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample] else { return }
        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            currentHR = bpm
            checkRecovery()
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

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.timerRemaining > 0 {
                    self.timerRemaining -= 1
                } else {
                    self.timerCompleted()
                }
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerRunning = false
        timerRemaining = 0
        recovered = false
        recoveryTargetHR = nil
    }

    private func timerCompleted() {
        WKInterfaceDevice.current().play(.success)
        stopTimer()
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
    private func startSimulation() {
        stopHRMonitoring()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let base: Double = self.timerRunning ? 130 : 85
                let noise = Double.random(in: -8...8)
                self.currentHR = base + noise
                self.checkRecovery()
            }
        }
    }
    #endif
}
