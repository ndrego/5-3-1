import Foundation
import CoreMotion
import WatchKit

/// Detects reps from Apple Watch accelerometer using peak detection.
@MainActor @Observable
final class RepCountingManager {
    var repCount: Int = 0
    var isActive: Bool = false
    var onRepCounted: ((Int) -> Void)?

    // User-tunable overrides (sent from phone)
    var sensitivityOverrides: [String: Double] = [:]  // profile key -> multiplier (1.0 = default)
    var tempoOverrides: [String: Double] = [:]        // profile key -> min seconds between reps

    private let motionManager = CMMotionManager()
    private var profile: LiftMotionProfile = .other
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

    // MARK: - Effective Tuning Values

    private var effectiveThreshold: Double {
        let base = profile.accelerationThreshold
        let multiplier = sensitivityOverrides[profile.key] ?? 1.0
        return base * multiplier
    }

    private var effectiveMinInterval: TimeInterval {
        tempoOverrides[profile.key] ?? profile.minPeakInterval
    }

    // MARK: - Peak Detection

    private func processMotion(accel: CMAcceleration, timestamp: TimeInterval) {
        let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

        // Exponential moving average
        smoothedValue = smoothingAlpha * magnitude + (1 - smoothingAlpha) * smoothedValue

        let threshold = effectiveThreshold
        let lowThreshold = threshold * 0.5

        switch state {
        case .idle:
            if smoothedValue > threshold {
                state = .rising
            }
        case .rising:
            if smoothedValue < lowThreshold {
                let timeSinceLastPeak = timestamp - lastPeakTime
                if lastPeakTime == 0 || timeSinceLastPeak >= effectiveMinInterval {
                    lastPeakTime = timestamp
                    repCount += 1
                    WKInterfaceDevice.current().play(.click)
                    onRepCounted?(repCount)
                }
                state = .idle
            }
        case .falling:
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

enum LiftMotionProfile: CaseIterable {
    // Main barbell lifts
    case squat, bench, deadlift, overheadPress
    // Accessory movement patterns
    case row, curl, pullUp, extension_, raiseFly, lunge, core
    // Catch-all
    case other

    var key: String {
        switch self {
        case .squat: return "squat"
        case .bench: return "bench"
        case .deadlift: return "deadlift"
        case .overheadPress: return "ohp"
        case .row: return "row"
        case .curl: return "curl"
        case .pullUp: return "pullup"
        case .extension_: return "extension"
        case .raiseFly: return "raise"
        case .lunge: return "lunge"
        case .core: return "core"
        case .other: return "other"
        }
    }

    var displayName: String {
        switch self {
        case .squat: return "Squat"
        case .bench: return "Bench"
        case .deadlift: return "Deadlift"
        case .overheadPress: return "OHP"
        case .row: return "Row"
        case .curl: return "Curl"
        case .pullUp: return "Pull-up / Pulldown"
        case .extension_: return "Extension / Pushdown"
        case .raiseFly: return "Raise / Fly"
        case .lunge: return "Lunge / Split Squat"
        case .core: return "Core"
        case .other: return "Other"
        }
    }

    var minPeakInterval: TimeInterval {
        switch self {
        case .squat: return 1.5
        case .bench: return 1.2
        case .deadlift: return 2.0
        case .overheadPress: return 1.5
        case .row: return 1.2
        case .curl: return 1.0
        case .pullUp: return 1.5
        case .extension_: return 0.8
        case .raiseFly: return 1.0
        case .lunge: return 1.5
        case .core: return 0.8
        case .other: return 1.0
        }
    }

    var accelerationThreshold: Double {
        switch self {
        case .squat: return 0.4
        case .bench: return 0.3
        case .deadlift: return 0.5
        case .overheadPress: return 0.4
        case .row: return 0.35
        case .curl: return 0.2
        case .pullUp: return 0.4
        case .extension_: return 0.2
        case .raiseFly: return 0.2
        case .lunge: return 0.4
        case .core: return 0.25
        case .other: return 0.3
        }
    }

    static func from(exerciseName: String) -> LiftMotionProfile {
        let lower = exerciseName.lowercased()

        // Main lifts
        if lower.contains("squat") && !lower.contains("split") { return .squat }
        if lower.contains("bench") && lower.contains("press") { return .bench }
        if lower.contains("deadlift") { return .deadlift }
        if lower.contains("overhead") || lower.contains("ohp") { return .overheadPress }
        if lower.contains("press") && !lower.contains("leg") && !lower.contains("push") {
            return .overheadPress
        }

        // Rows
        if lower.contains("row") { return .row }

        // Curls
        if lower.contains("curl") { return .curl }

        // Pull-ups / Pulldowns
        if lower.contains("pull-up") || lower.contains("pull up") || lower.contains("pullup") ||
           lower.contains("chin-up") || lower.contains("chin up") || lower.contains("chinup") ||
           lower.contains("pulldown") || lower.contains("lat pull") { return .pullUp }

        // Extensions / Pushdowns
        if lower.contains("pushdown") || lower.contains("push down") ||
           lower.contains("skull") || lower.contains("tricep") ||
           lower.contains("extension") { return .extension_ }

        // Raises / Flys
        if lower.contains("raise") || lower.contains("fly") || lower.contains("lateral") ||
           lower.contains("reverse fly") || lower.contains("face pull") { return .raiseFly }

        // Lunges / Split squats
        if lower.contains("lunge") || lower.contains("split squat") ||
           lower.contains("step-up") || lower.contains("step up") ||
           lower.contains("bulgarian") { return .lunge }

        // Core
        if lower.contains("crunch") || lower.contains("sit up") || lower.contains("sit-up") ||
           lower.contains("plank") || lower.contains("ab ") || lower.contains("ab wheel") ||
           lower.contains("leg raise") || lower.contains("knee raise") ||
           lower.contains("side bend") || lower.contains("back extension") { return .core }

        // Remaining presses (close-grip bench, dips)
        if lower.contains("dip") || lower.contains("push-up") || lower.contains("push up") {
            return .bench
        }

        return .other
    }
}
