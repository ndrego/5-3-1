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

    // Calibration
    enum CalibrationPhase: Equatable {
        case idle
        case countdown(Int)
        case recording
        case sending
    }
    var calibrationPhase: CalibrationPhase = .idle
    var onCalibrationSamples: ((_ magnitudes: [Double], _ timestamps: [Double]) -> Void)?
    private var calibrationRecorder: CalibrationRecorder?
    private var calibrationTask: Task<Void, Never>?

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

    // MARK: - Calibration

    func startCalibration() {
        guard calibrationPhase == .idle else { return }
        print("[Calibration] Starting calibration sequence")
        // Stop any existing rep counting
        motionHelper?.stop()
        motionHelper = nil
        peakDetector = nil
        isActive = false

        calibrationTask = Task {
            for i in stride(from: 3, through: 1, by: -1) {
                calibrationPhase = .countdown(i)
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(1))
            }

            calibrationPhase = .recording
            WKInterfaceDevice.current().play(.start)

            let recorder = CalibrationRecorder()
            self.calibrationRecorder = recorder
            recorder.start()

            // Record up to 20 seconds — user can tap Done to finish early
            try? await Task.sleep(for: .seconds(20))

            // If still recording (wasn't finished early), send now
            if calibrationPhase == .recording {
                sendCalibrationData()
            }
        }
    }

    /// Called when the user taps Done on the watch during recording.
    func finishCalibration() {
        guard calibrationPhase == .recording else { return }
        calibrationTask?.cancel()
        sendCalibrationData()
    }

    private func sendCalibrationData() {
        calibrationRecorder?.stop()
        calibrationPhase = .sending

        let (magnitudes, timestamps) = calibrationRecorder?.getSamples() ?? ([], [])
        print("[Calibration] Recorded \(magnitudes.count) samples, sending to phone")

        onCalibrationSamples?(magnitudes, timestamps)

        WKInterfaceDevice.current().play(.success)
        calibrationRecorder = nil
        calibrationTask = nil
        calibrationPhase = .idle
    }

    func cancelCalibration() {
        calibrationTask?.cancel()
        calibrationRecorder?.stop()
        calibrationRecorder = nil
        calibrationTask = nil
        calibrationPhase = .idle
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

/// Detects reps using vertical acceleration (projected onto gravity axis).
///
/// Models the physics of a rep: every rep involves two acceleration events:
/// 1. Accelerate in one direction (e.g. descend in squat)
/// 2. Decelerate/reverse at the turning point
/// 3. Accelerate back (e.g. stand up)
/// 4. Decelerate at the top → baseline
///
/// On absolute vertical acceleration, this shows as: peak → valley → peak.
/// The detector requires this double-peak pattern to count one rep.
/// A single peak (arm swing, bump) is ignored.
final class PeakDetector: @unchecked Sendable {
    private var threshold: Double
    private var lowThreshold: Double
    private var baseMinInterval: TimeInterval
    private var adaptiveMinInterval: TimeInterval
    private let smoothingAlpha: Double = 0.3

    // Maximum time allowed between the two peaks of a single rep.
    private let maxPeakGap: TimeInterval = 3.0

    private var smoothedVertical: Double = 0
    private var lastRepTime: TimeInterval = 0
    private var repCount: Int = 0
    private var sampleCount: Int = 0
    private var state: State = .idle
    private var firstPeakTime: TimeInterval = 0

    // Autocorrelation buffer: ~6 seconds at 50Hz = 300 samples
    private let bufferSize = 300
    private var signalBuffer: [Double] = []
    private var lastAutoCorrelationSample: Int = 0

    private enum State {
        case idle       // waiting for first peak above threshold
        case peak1      // first peak detected, above threshold
        case valley     // dropped below threshold after first peak, waiting for second
        case peak2      // second peak detected — rep complete when it drops
    }

    init(threshold: Double, minInterval: TimeInterval) {
        self.threshold = threshold
        self.lowThreshold = threshold * 0.55
        self.baseMinInterval = minInterval
        self.adaptiveMinInterval = minInterval
        self.signalBuffer.reserveCapacity(bufferSize)
    }

    func reset(threshold: Double, minInterval: TimeInterval) {
        self.threshold = threshold
        self.lowThreshold = threshold * 0.55
        self.baseMinInterval = minInterval
        self.adaptiveMinInterval = minInterval
        smoothedVertical = 0
        lastRepTime = 0
        repCount = 0
        sampleCount = 0
        firstPeakTime = 0
        state = .idle
        signalBuffer.removeAll(keepingCapacity: true)
        lastAutoCorrelationSample = 0
    }

    /// Process a sample with absolute vertical acceleration.
    /// Returns rep count if a new rep was detected, nil otherwise.
    func processSample(magnitude: Double, timestamp: TimeInterval) -> Int? {
        sampleCount += 1
        smoothedVertical = smoothingAlpha * magnitude + (1 - smoothingAlpha) * smoothedVertical

        // Fill circular buffer for autocorrelation
        if signalBuffer.count < bufferSize {
            signalBuffer.append(smoothedVertical)
        } else {
            signalBuffer[sampleCount % bufferSize] = smoothedVertical
        }

        // Run autocorrelation every ~1 second (50 samples) once we have enough data
        if signalBuffer.count >= bufferSize && (sampleCount - lastAutoCorrelationSample) >= 50 {
            lastAutoCorrelationSample = sampleCount
            updateAdaptiveInterval()
        }

        if sampleCount <= 3 || sampleCount % 50 == 0 {
            print("[RepCount] #\(sampleCount): vert=\(String(format: "%.3f", smoothedVertical)) thresh=\(String(format: "%.3f", threshold)) interval=\(String(format: "%.2f", adaptiveMinInterval))s state=\(state)")
        }

        // Effective lockout: use adaptive interval (from autocorrelation) with a floor
        let lockout = max(adaptiveMinInterval * 0.7, baseMinInterval * 0.4)

        switch state {
        case .idle:
            if smoothedVertical > threshold {
                if lastRepTime == 0 || (timestamp - lastRepTime) >= lockout {
                    state = .peak1
                    firstPeakTime = timestamp
                }
            }

        case .peak1:
            if smoothedVertical < lowThreshold {
                state = .valley
            }

        case .valley:
            if smoothedVertical > threshold {
                state = .peak2
            } else if timestamp - firstPeakTime > maxPeakGap {
                state = .idle
                firstPeakTime = 0
            }

        case .peak2:
            if smoothedVertical < lowThreshold {
                lastRepTime = timestamp
                repCount += 1
                let gap = timestamp - firstPeakTime
                state = .idle
                firstPeakTime = 0
                print("[RepCount] Rep #\(repCount) (double-peak, gap=\(String(format: "%.2f", gap))s)")
                return repCount
            } else if timestamp - firstPeakTime > maxPeakGap {
                state = .idle
                firstPeakTime = 0
            }
        }
        return nil
    }

    // MARK: - Autocorrelation

    /// Estimate the dominant repetition period from the signal buffer.
    /// Updates adaptiveMinInterval so the lockout tracks the user's actual tempo.
    private func updateAdaptiveInterval() {
        let n = signalBuffer.count
        guard n >= bufferSize else { return }

        // Compute mean
        var sum = 0.0
        for v in signalBuffer { sum += v }
        let mean = sum / Double(n)

        // Autocorrelation for lags corresponding to 0.8s – 5s (40–250 samples at 50Hz)
        let minLag = 40   // 0.8s — fastest possible rep
        let maxLag = min(250, n / 2)  // 5s or half the buffer
        guard minLag < maxLag else { return }

        // Compute variance (lag 0) for normalization
        var variance = 0.0
        for v in signalBuffer {
            let d = v - mean
            variance += d * d
        }
        guard variance > 1e-10 else { return }

        var bestLag = 0
        var bestCorr = 0.0

        for lag in minLag...maxLag {
            var corr = 0.0
            for i in 0..<(n - lag) {
                corr += (signalBuffer[i] - mean) * (signalBuffer[(i + lag) % n] - mean)
            }
            corr /= variance  // normalized autocorrelation

            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        // Only trust the autocorrelation if the peak is strong enough
        // (> 0.3 means clear periodicity in the signal)
        if bestCorr > 0.3 && bestLag > 0 {
            let estimatedPeriod = Double(bestLag) / 50.0  // convert samples to seconds
            // Blend with base interval: use the longer of the two to be conservative
            // but never exceed 2x base (don't let one slow rep break everything)
            let clamped = min(estimatedPeriod, baseMinInterval * 2.0)
            adaptiveMinInterval = max(clamped, baseMinInterval * 0.5)
            print("[RepCount] Autocorrelation: period=\(String(format: "%.2f", estimatedPeriod))s corr=\(String(format: "%.2f", bestCorr)) → interval=\(String(format: "%.2f", adaptiveMinInterval))s")
        }
    }
}

// MARK: - CoreMotion Helper (non-MainActor)

/// Separate class to own CMMotionManager and its callbacks, avoiding Swift 6
/// isolation crashes when callbacks fire on a background OperationQueue.
/// Uses device motion at 50Hz for gravity-removed acceleration via sensor fusion.
final class MotionHelper: @unchecked Sendable {
    // Apple requires only ONE CMMotionManager per app
    nonisolated(unsafe) static let sharedMotionManager = CMMotionManager()
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
        let mm = Self.sharedMotionManager

        // Stop any prior updates on the shared manager
        mm.stopDeviceMotionUpdates()
        mm.stopAccelerometerUpdates()

        if mm.isDeviceMotionAvailable {
            mm.deviceMotionUpdateInterval = 1.0 / 50.0
            print("[RepCount] Starting device motion at 50Hz (vertical axis)")
            mm.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
                guard let self else { return }
                self.callbackCount += 1
                if let error {
                    print("[RepCount] Device motion error: \(error)")
                    return
                }
                guard let data else { return }

                // Project userAcceleration onto gravity direction to get vertical component.
                // gravity vector points toward Earth (~0, ~0, ~-1 when flat).
                // Dot product gives acceleration along the vertical axis.
                let g = data.gravity
                let ua = data.userAcceleration
                let gravMag = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
                let verticalAccel: Double
                if gravMag > 0.01 {
                    // Signed vertical: positive = upward, negative = downward
                    // Use absolute value — we care about motion magnitude, not direction
                    verticalAccel = abs((ua.x * g.x + ua.y * g.y + ua.z * g.z) / gravMag)
                } else {
                    verticalAccel = 0
                }

                if self.callbackCount <= 3 || self.callbackCount % 50 == 0 {
                    let totalMag = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
                    print("[RepCount] motion #\(self.callbackCount) vert=\(String(format: "%.3f", verticalAccel)) mag=\(String(format: "%.3f", totalMag))")
                }

                if let repNum = self.detector.processSample(magnitude: verticalAccel, timestamp: data.timestamp) {
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
        Self.sharedMotionManager.stopDeviceMotionUpdates()
        Self.sharedMotionManager.stopAccelerometerUpdates()
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

// MARK: - Calibration Recorder (non-MainActor)

/// Records vertical acceleration (gravity-projected) for calibration analysis on the phone.
final class CalibrationRecorder: @unchecked Sendable {
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    private let lock = NSLock()
    private var _magnitudes: [Double] = []
    private var _timestamps: [Double] = []

    func getSamples() -> (magnitudes: [Double], timestamps: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        return (_magnitudes, _timestamps)
    }

    func start() {
        let mm = MotionHelper.sharedMotionManager
        mm.stopDeviceMotionUpdates()
        mm.stopAccelerometerUpdates()

        if mm.isDeviceMotionAvailable {
            mm.deviceMotionUpdateInterval = 1.0 / 50.0
            print("[Calibration] Starting device motion recording at 50Hz (vertical axis)")
            mm.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
                guard let self, let data, error == nil else { return }
                let g = data.gravity
                let ua = data.userAcceleration
                let gravMag = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
                let vertical: Double
                if gravMag > 0.01 {
                    vertical = abs((ua.x * g.x + ua.y * g.y + ua.z * g.z) / gravMag)
                } else {
                    vertical = 0
                }
                self.lock.lock()
                self._magnitudes.append(vertical)
                self._timestamps.append(data.timestamp)
                self.lock.unlock()
            }
        } else if mm.isAccelerometerAvailable {
            mm.accelerometerUpdateInterval = 1.0 / 50.0
            print("[Calibration] Starting accelerometer recording at 50Hz (fallback)")
            mm.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
                guard let self, let data, error == nil else { return }
                let accel = data.acceleration
                let rawMag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
                let magnitude = abs(rawMag - 1.0)
                self.lock.lock()
                self._magnitudes.append(magnitude)
                self._timestamps.append(data.timestamp)
                self.lock.unlock()
            }
        }
    }

    func stop() {
        MotionHelper.sharedMotionManager.stopDeviceMotionUpdates()
        MotionHelper.sharedMotionManager.stopAccelerometerUpdates()
    }
}
