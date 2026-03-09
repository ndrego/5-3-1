import Foundation
import CoreMotion
import WatchKit

/// Detects reps from Apple Watch accelerometer using peak detection.
@MainActor @Observable
final class RepCountingManager {
    var repCount: Int = 0
    var isActive: Bool = false
    var onRepCounted: ((Int) -> Void)?

    private let motionManager = CMMotionManager()
    private var profile: LiftMotionProfile = .generic
    private var lastPeakTime: TimeInterval = 0
    private var smoothedValue: Double = 0
    private var state: DetectionState = .idle
    private let smoothingAlpha: Double = 0.3
    private let motionQueue = OperationQueue()

    #if DEBUG && targetEnvironment(simulator)
    private var simulationTimer: Timer?
    #endif

    private enum DetectionState {
        case idle, rising, falling
    }

    func startCounting(exerciseName: String) {
        repCount = 0
        smoothedValue = 0
        lastPeakTime = 0
        state = .idle
        profile = LiftMotionProfile.from(exerciseName: exerciseName)
        isActive = true

        #if DEBUG && targetEnvironment(simulator)
        startSimulation()
        return
        #else
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let accel = motion.userAcceleration
            let timestamp = motion.timestamp
            Task { @MainActor [weak self] in
                self?.processMotion(accel: accel, timestamp: timestamp)
            }
        }
        #endif
    }

    func stopCounting() -> Int {
        isActive = false
        #if DEBUG && targetEnvironment(simulator)
        simulationTimer?.invalidate()
        simulationTimer = nil
        #else
        motionManager.stopDeviceMotionUpdates()
        #endif
        return repCount
    }

    func resetCount() {
        repCount = 0
    }

    // MARK: - Peak Detection

    private func processMotion(accel: CMAcceleration, timestamp: TimeInterval) {
        // Use magnitude of acceleration vector for orientation-independence
        let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

        // Exponential moving average
        smoothedValue = smoothingAlpha * magnitude + (1 - smoothingAlpha) * smoothedValue

        let threshold = profile.accelerationThreshold
        let lowThreshold = threshold * 0.5

        switch state {
        case .idle:
            if smoothedValue > threshold {
                state = .rising
            }
        case .rising:
            if smoothedValue < lowThreshold {
                // Crossed above threshold and back down — that's one rep
                let timeSinceLastPeak = timestamp - lastPeakTime
                if lastPeakTime == 0 || timeSinceLastPeak >= profile.minPeakInterval {
                    lastPeakTime = timestamp
                    repCount += 1
                    WKInterfaceDevice.current().play(.click)
                    onRepCounted?(repCount)
                }
                state = .idle
            }
        case .falling:
            // Not used in current algorithm but reserved
            state = .idle
        }
    }

    // MARK: - Simulation

    #if DEBUG && targetEnvironment(simulator)
    private func startSimulation() {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.repCount += 1
                WKInterfaceDevice.current().play(.click)
                self.onRepCounted?(self.repCount)
            }
        }
    }
    #endif
}

// MARK: - Lift Motion Profiles

enum LiftMotionProfile {
    case squat, bench, deadlift, overheadPress, generic

    var minPeakInterval: TimeInterval {
        switch self {
        case .squat: return 1.5
        case .bench: return 1.2
        case .deadlift: return 2.0
        case .overheadPress: return 1.5
        case .generic: return 1.0
        }
    }

    var accelerationThreshold: Double {
        switch self {
        case .squat: return 0.4
        case .bench: return 0.3
        case .deadlift: return 0.5
        case .overheadPress: return 0.4
        case .generic: return 0.3
        }
    }

    static func from(exerciseName: String) -> LiftMotionProfile {
        let lower = exerciseName.lowercased()
        if lower.contains("squat") { return .squat }
        if lower.contains("bench") { return .bench }
        if lower.contains("deadlift") { return .deadlift }
        if lower.contains("overhead") || lower.contains("ohp") {
            return .overheadPress
        }
        if lower.contains("press") && !lower.contains("bench") && !lower.contains("leg") {
            return .overheadPress
        }
        return .generic
    }
}
