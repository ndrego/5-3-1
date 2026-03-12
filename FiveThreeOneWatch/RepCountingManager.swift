import Foundation
import CoreMotion
import WatchKit

/// Detects reps from Apple Watch accelerometer using peak detection.
@MainActor @Observable
final class RepCountingManager {
    var repCount: Int = 0
    var isActive: Bool = false
    var onRepCounted: ((Int) -> Void)?
    private var motionAuthorized = false

    // User-tunable overrides (sent from phone)
    var sensitivityOverrides: [String: Double] = [:]  // profile key -> multiplier (1.0 = default)
    var tempoOverrides: [String: Double] = [:]        // profile key -> min seconds between reps

    private var peakDetector: PeakDetector?
    private var motionHelper: MotionHelper?

    #if DEBUG && targetEnvironment(simulator)
    private var simulationTimer: Timer?
    #endif

    /// Request motion authorization by querying CMMotionActivityManager (triggers system prompt).
    func requestMotionAuthorization() {
        let status = CMMotionActivityManager.authorizationStatus()
        print("[RepCount] Motion authorization status: \(status.rawValue)")
        if status == .authorized {
            motionAuthorized = true
            return
        }
        let activityManager = CMMotionActivityManager()
        let now = Date()
        activityManager.queryActivityStarting(from: now.addingTimeInterval(-1), to: now, to: OperationQueue.main) { [weak self] _, error in
            if let error {
                print("[RepCount] Motion auth query error: \(error.localizedDescription)")
            }
            let newStatus = CMMotionActivityManager.authorizationStatus()
            print("[RepCount] Motion authorization after prompt: \(newStatus.rawValue)")
            DispatchQueue.main.async {
                self?.motionAuthorized = (newStatus == .authorized)
            }
        }
    }

    private var currentExercise: String = ""

    func startCounting(exerciseName: String) {
        print("[RepCount] startCounting for: \(exerciseName)")
        currentExercise = exerciseName
        repCount = 0
        isActive = true

        let profile = LiftMotionProfile.from(exerciseName: exerciseName)
        let threshold = profile.accelerationThreshold * (sensitivityOverrides[profile.key] ?? 1.0)
        let minInterval = tempoOverrides[profile.key] ?? profile.minPeakInterval

        if let existing = peakDetector {
            existing.reset(threshold: threshold, minInterval: minInterval)
        } else {
            peakDetector = PeakDetector(threshold: threshold, minInterval: minInterval)
        }

        #if DEBUG && targetEnvironment(simulator)
        startSimulation()
        return
        #else
        startSensor()
        #endif
    }

    func stopCounting() -> Int {
        print("[RepCount] stopCounting called, was isActive=\(isActive)")
        Thread.callStackSymbols.prefix(6).forEach { print("[RepCount] \($0)") }
        isActive = false
        currentExercise = ""
        #if DEBUG && targetEnvironment(simulator)
        simulationTimer?.invalidate()
        simulationTimer = nil
        #endif
        return repCount
    }

    /// Stop the sensor entirely (call when workout ends).
    func stopAccelerometer() {
        print("[RepCount] stopAccelerometer called, was isActive=\(isActive)")
        motionHelper?.stop()
        motionHelper = nil
        peakDetector = nil
        isActive = false
        currentExercise = ""
    }

    private func startSensor() {
        guard motionHelper == nil, let detector = peakDetector else {
            print("[RepCount] Sensor already running or no detector")
            return
        }

        // Strong capture is intentional — the retain cycle
        // (self → motionHelper → onRepDetected → self) is broken
        // by stopAccelerometer() setting motionHelper = nil.
        let helper = MotionHelper(detector: detector) { [self] count in
            print("[RepCount] onRepDetected called with count=\(count), dispatching to main")
            DispatchQueue.main.async {
                print("[RepCount] main queue: isActive=\(self.isActive)")
                guard self.isActive else { return }
                self.repCount = count
                print("[RepCount] Rep #\(count) detected")
                WKInterfaceDevice.current().play(.start)
                self.onRepCounted?(count)
            }
        }
        self.motionHelper = helper
        helper.start()
    }

    func resetCount() {
        repCount = 0
    }

    // MARK: - Simulation

    #if DEBUG && targetEnvironment(simulator)
    private func startSimulation() {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                self.repCount += 1
                WKInterfaceDevice.current().play(.click)
                self.onRepCounted?(self.repCount)
            }
        }
    }
    #endif
}

// MARK: - Peak Detector (runs on background motion queue)

/// Performs all signal processing on the motion OperationQueue.
/// Returns the rep number when a rep is detected, nil otherwise.
final class PeakDetector: @unchecked Sendable {
    private var threshold: Double
    private var lowThreshold: Double
    private var minInterval: TimeInterval
    private let smoothingAlpha: Double = 0.45

    private var smoothedValue: Double = 0
    private var lastPeakTime: TimeInterval = 0
    private var repCount: Int = 0
    private var sampleCount: Int = 0
    private var state: State = .idle

    private enum State {
        case idle, rising
    }

    init(threshold: Double, minInterval: TimeInterval) {
        self.threshold = threshold
        self.lowThreshold = threshold * 0.5
        self.minInterval = minInterval
    }

    func reset(threshold: Double, minInterval: TimeInterval) {
        self.threshold = threshold
        self.lowThreshold = threshold * 0.5
        self.minInterval = minInterval
        smoothedValue = 0
        lastPeakTime = 0
        repCount = 0
        sampleCount = 0
        state = .idle
    }

    /// Process a sample. Returns rep count if a new rep was detected, nil otherwise.
    func processSample(magnitude: Double, timestamp: TimeInterval) -> Int? {
        sampleCount += 1
        smoothedValue = smoothingAlpha * magnitude + (1 - smoothingAlpha) * smoothedValue

        if sampleCount <= 3 || sampleCount % 25 == 0 {
            print("[RepCount] detect #\(sampleCount): smoothed=\(String(format: "%.3f", smoothedValue)) thresh=\(String(format: "%.3f", threshold)) state=\(state)")
        }

        switch state {
        case .idle:
            if smoothedValue > threshold {
                state = .rising
            }
        case .rising:
            if smoothedValue < lowThreshold {
                state = .idle
                let timeSinceLastPeak = timestamp - lastPeakTime
                if lastPeakTime == 0 || timeSinceLastPeak >= minInterval {
                    lastPeakTime = timestamp
                    repCount += 1
                    return repCount
                }
            }
        }
        return nil
    }
}

// MARK: - CoreMotion Helper (non-MainActor)

/// Separate class to own CMMotionManager and its callbacks, avoiding Swift 6
/// isolation crashes when callbacks fire on a background OperationQueue.
/// Uses device motion at 50Hz for gravity-removed acceleration via sensor fusion.
final class MotionHelper: @unchecked Sendable {
    // Apple requires only ONE CMMotionManager per app
    nonisolated(unsafe) private static let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    private let detector: PeakDetector
    private let onRepDetected: @Sendable (Int) -> Void
    private var callbackCount = 0

    init(detector: PeakDetector, onRepDetected: @escaping @Sendable (Int) -> Void) {
        self.detector = detector
        self.onRepDetected = onRepDetected
    }

    func start() {
        let mm = Self.motionManager

        // Stop any prior updates on the shared manager
        mm.stopDeviceMotionUpdates()
        mm.stopAccelerometerUpdates()

        if mm.isDeviceMotionAvailable {
            mm.deviceMotionUpdateInterval = 1.0 / 50.0
            print("[RepCount] Starting device motion at 50Hz")
            mm.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
                guard let self else { return }
                self.callbackCount += 1
                if let error {
                    print("[RepCount] Device motion error: \(error)")
                    return
                }
                guard let data else { return }

                // userAcceleration has gravity removed by sensor fusion
                let ua = data.userAcceleration
                let magnitude = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)

                if self.callbackCount <= 3 || self.callbackCount % 50 == 0 {
                    print("[RepCount] motion #\(self.callbackCount) mag=\(String(format: "%.3f", magnitude))")
                }

                if let repNum = self.detector.processSample(magnitude: magnitude, timestamp: data.timestamp) {
                    self.onRepDetected(repNum)
                }
            }
        } else if mm.isAccelerometerAvailable {
            mm.accelerometerUpdateInterval = 1.0 / 50.0
            print("[RepCount] Starting accelerometer at 50Hz (fallback)")
            mm.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
                guard let self else { return }
                self.callbackCount += 1
                if let error {
                    print("[RepCount] Accelerometer error: \(error)")
                    return
                }
                guard let data else { return }

                let accel = data.acceleration
                let rawMag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
                let magnitude = abs(rawMag - 1.0)

                if self.callbackCount <= 3 || self.callbackCount % 50 == 0 {
                    print("[RepCount] accel #\(self.callbackCount) mag=\(String(format: "%.3f", magnitude))")
                }

                if let repNum = self.detector.processSample(magnitude: magnitude, timestamp: data.timestamp) {
                    self.onRepDetected(repNum)
                }
            }
        } else {
            print("[RepCount] No motion sensors available!")
        }
    }

    func stop() {
        Self.motionManager.stopDeviceMotionUpdates()
        Self.motionManager.stopAccelerometerUpdates()
    }
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
        case .squat: return 0.50
        case .bench: return 0.40
        case .deadlift: return 0.65
        case .overheadPress: return 0.50
        case .row: return 0.45
        case .curl: return 0.28
        case .pullUp: return 0.50
        case .extension_: return 0.25
        case .raiseFly: return 0.28
        case .lunge: return 0.50
        case .core: return 0.32
        case .other: return 0.40
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
