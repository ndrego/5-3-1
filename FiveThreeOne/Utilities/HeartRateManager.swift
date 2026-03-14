import Foundation
import HealthKit

/// Manages live heart rate streaming from Apple Watch via HealthKit.
@MainActor @Observable
final class HeartRateManager {
    private let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var setStartTime: Date?
    private var setHRSamples: [Double] = []
    private var simulationTimer: Timer?

    // Published state
    var currentHR: Double = 0
    var isAuthorized = false
    var isMonitoring = false
    var allSessionSamples: [Double] = []

    #if DEBUG
    var isSimulating = false
    #endif

    // MARK: - Authorization

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isAvailable else { return }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let readTypes: Set<HKObjectType> = [heartRateType, activeEnergy]
        let writeTypes: Set<HKSampleType> = [HKWorkoutType.workoutType(), activeEnergy]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    /// Save a completed workout to HealthKit so it appears in the Fitness app.
    func saveWorkoutToHealthKit(
        start: Date,
        end: Date,
        calories: Double?,
        averageHR: Double?
    ) async {
        guard isAvailable, isAuthorized else {
            print("HealthKit save skipped: available=\(isAvailable) authorized=\(isAuthorized)")
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: start)

            // Add calorie sample if available
            if let calories, calories > 0 {
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: energyQuantity,
                    start: start,
                    end: end
                )
                try await builder.addSamples([energySample])
            }

            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
            print("HealthKit workout saved successfully")
        } catch {
            print("Failed to save workout to HealthKit: \(error.localizedDescription)")
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        #if DEBUG
        if isSimulating {
            startSimulation()
            return
        }
        #endif

        guard isAuthorized else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        stopMonitoring()
        allSessionSamples = []

        let predicate = HKQuery.predicateForSamples(
            withStart: .now,
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            Task { @MainActor [weak self] in
                self?.processSamples(samples)
            }
        }

        query.updateHandler = { _, samples, _, _, _ in
            Task { @MainActor [weak self] in
                self?.processSamples(samples)
            }
        }

        healthStore.execute(query)
        self.query = query
        isMonitoring = true
    }

    func stopMonitoring() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
        simulationTimer?.invalidate()
        simulationTimer = nil
        isMonitoring = false
    }

    // MARK: - Per-Set Tracking

    /// Call when a set begins to start averaging HR for that set.
    func markSetStart() {
        setStartTime = .now
        setHRSamples = []
    }

    /// Ensure set tracking is active without clearing existing samples.
    func ensureSetTracking() {
        if setStartTime == nil {
            setStartTime = .now
        }
    }

    /// Call when a set ends. Returns average HR and all samples during the set.
    /// Falls back to current HR if no samples were collected during the set interval.
    func markSetEnd() -> (average: Double, samples: [Double])? {
        defer {
            setStartTime = nil
            setHRSamples = []
        }
        if !setHRSamples.isEmpty {
            let avg = setHRSamples.reduce(0, +) / Double(setHRSamples.count)
            return (average: avg, samples: setHRSamples)
        }
        // Fallback: use current HR if available (e.g. watch HR arrived but no samples in this interval)
        if currentHR > 0 {
            return (average: currentHR, samples: [currentHR])
        }
        return nil
    }

    /// Estimate RPE (1-10 scale) from heart rate as percentage of max HR.
    /// Uses age-predicted max HR (220 - age).
    static func estimateRPE(heartRate: Double, age: Int) -> Double {
        let maxHR = Double(220 - age)
        guard maxHR > 0 else { return 1 }
        let pctMax = heartRate / maxHR

        // Map HR% to RPE 1-10 scale
        // ~40% → 1, 50% → 2, 60% → 4, 70% → 6, 80% → 8, 90%+ → 10
        let rpe = (pctMax - 0.35) / 0.065
        return min(10, max(1, rpe))
    }

    /// Session average HR.
    var sessionAverageHR: Double? {
        guard !allSessionSamples.isEmpty else { return nil }
        return allSessionSamples.reduce(0, +) / Double(allSessionSamples.count)
    }

    /// Calorie estimate using the Keytel et al. (2005) HR-based formula.
    /// Accounts for sex, age, weight, average HR, and duration.
    static func estimateCalories(
        averageHR: Double,
        durationMinutes: Double,
        bodyWeightKg: Double = 80,
        age: Int = 30,
        isMale: Bool = true
    ) -> Double {
        let hr = averageHR
        let wt = bodyWeightKg
        let a = Double(age)
        let t = durationMinutes

        // Keytel et al. gender-specific equations (kcal/min)
        let caloriesPerMinute: Double
        if isMale {
            caloriesPerMinute = max(0, (-55.0969 + 0.6309 * hr + 0.1988 * wt + 0.2017 * a) / 4.184)
        } else {
            caloriesPerMinute = max(0, (-20.4022 + 0.4472 * hr - 0.1263 * wt + 0.074 * a) / 4.184)
        }
        return caloriesPerMinute * t
    }

    // MARK: - Private

    private func processSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample] else { return }

        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            recordBPM(bpm)
        }
    }

    /// Record a heart rate reading from any source (HealthKit query or watch connectivity).
    func recordBPM(_ bpm: Double) {
        currentHR = bpm
        allSessionSamples.append(bpm)

        if setStartTime != nil {
            setHRSamples.append(bpm)
        }
    }

    // MARK: - Simulation (DEBUG only)

    #if DEBUG
    /// Starts generating fake HR data for simulator testing.
    func startSimulation() {
        stopMonitoring()
        allSessionSamples = []
        isMonitoring = true
        isSimulating = true

        // Generate a new HR sample every ~2 seconds
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Simulate HR between 65-165 with some variance
                let base: Double = self.setStartTime != nil ? 140 : 85  // Higher during sets
                let noise = Double.random(in: -8...8)
                self.recordBPM(base + noise)
            }
        }
    }
    #endif
}
