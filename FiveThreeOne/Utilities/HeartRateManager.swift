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

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            isAuthorized = false
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

    /// Call when a set ends. Returns the average HR during the set, or nil.
    func markSetEnd() -> Double? {
        defer {
            setStartTime = nil
            setHRSamples = []
        }
        guard !setHRSamples.isEmpty else { return nil }
        return setHRSamples.reduce(0, +) / Double(setHRSamples.count)
    }

    /// Session average HR.
    var sessionAverageHR: Double? {
        guard !allSessionSamples.isEmpty else { return nil }
        return allSessionSamples.reduce(0, +) / Double(allSessionSamples.count)
    }

    /// Rough calorie estimate using average HR, duration, and body weight.
    static func estimateCalories(
        averageHR: Double,
        durationMinutes: Double,
        bodyWeightKg: Double = 80
    ) -> Double {
        let caloriesPerMinute = max(0, (0.6309 * averageHR + 0.1988 * bodyWeightKg - 55.0969) / 4.184)
        return caloriesPerMinute * durationMinutes
    }

    // MARK: - Private

    private func processSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample] else { return }

        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            recordBPM(bpm)
        }
    }

    private func recordBPM(_ bpm: Double) {
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
