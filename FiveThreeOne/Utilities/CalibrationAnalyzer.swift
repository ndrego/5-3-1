import Foundation

/// Analyzes raw accelerometer samples from a calibration recording to compute
/// optimal sensitivity multiplier and tempo for rep counting.
struct CalibrationAnalyzer {
    struct Result {
        let sensitivityMultiplier: Double
        let tempo: Double
        let peaksFound: Int
    }

    /// Analyze calibration samples and return tuning parameters.
    /// - Parameters:
    ///   - magnitudes: Raw acceleration magnitudes from the watch (50Hz)
    ///   - timestamps: Corresponding timestamps
    ///   - baseThreshold: The default acceleration threshold for this lift profile
    ///   - baseTempo: The default min peak interval for this lift profile
    static func analyze(
        magnitudes: [Double],
        timestamps: [Double],
        baseThreshold: Double,
        baseTempo: Double
    ) -> Result? {
        guard magnitudes.count == timestamps.count, magnitudes.count > 100 else {
            print("[Calibration] Not enough samples: \(magnitudes.count)")
            return nil
        }

        // Apply EMA smoothing (same alpha as PeakDetector on watch)
        let alpha = 0.45
        var smoothed = [Double]()
        var ema = 0.0
        for mag in magnitudes {
            ema = alpha * mag + (1 - alpha) * ema
            smoothed.append(ema)
        }

        // Noise floor: 20th percentile of smoothed values
        let sortedSmoothed = smoothed.sorted()
        let noiseFloor = sortedSmoothed[sortedSmoothed.count / 5]

        // Peaks must be well above noise
        let minPeakHeight = max(noiseFloor * 4, 0.08)

        // Find local maxima (check 5 samples on each side)
        struct Peak {
            let index: Int
            let magnitude: Double
            let timestamp: Double
        }

        let window = 5
        var peaks: [Peak] = []
        for i in window..<(smoothed.count - window) {
            let val = smoothed[i]
            if val < minPeakHeight { continue }
            var isMax = true
            for j in (i - window)..<i {
                if smoothed[j] >= val { isMax = false; break }
            }
            if !isMax { continue }
            for j in (i + 1)...(i + window) {
                if smoothed[j] >= val { isMax = false; break }
            }
            if isMax {
                peaks.append(Peak(index: i, magnitude: val, timestamp: timestamps[i]))
            }
        }

        print("[Calibration] Found \(peaks.count) raw peaks above minHeight \(String(format: "%.3f", minPeakHeight))")

        guard peaks.count >= 2 else {
            print("[Calibration] Not enough peaks found: \(peaks.count)")
            return nil
        }

        // Merge peaks within 1.0s — each rep's up/down phases produce multiple peaks
        // within ~0.5-1.0s; keep the largest from each cluster
        var merged: [Peak] = []
        var i = 0
        while i < peaks.count {
            var best = peaks[i]
            while i + 1 < peaks.count && (peaks[i + 1].timestamp - best.timestamp) < 1.0 {
                i += 1
                if peaks[i].magnitude > best.magnitude {
                    best = peaks[i]
                }
            }
            merged.append(best)
            i += 1
        }

        print("[Calibration] After merging: \(merged.count) peaks")

        guard merged.count >= 2 else {
            print("[Calibration] Not enough merged peaks: \(merged.count)")
            return nil
        }

        // Take the 3 strongest peaks (we asked the user for 3 reps), sorted by time
        let strongest = merged.sorted { $0.magnitude > $1.magnitude }.prefix(min(merged.count, 3))
        let ordered = strongest.sorted { $0.timestamp < $1.timestamp }

        // Median peak magnitude
        let peakMags = ordered.map(\.magnitude).sorted()
        let medianPeak = peakMags[peakMags.count / 2]

        // Threshold: 50% of median peak — the PeakDetector uses threshold for
        // rising edge and threshold*0.5 for falling edge, so 50% of the actual
        // peak gives comfortable headroom on both sides
        let computedThreshold = medianPeak * 0.5

        // Intervals between consecutive peaks (rep-to-rep timing)
        var intervals: [Double] = []
        for j in 1..<ordered.count {
            let dt = ordered[j].timestamp - ordered[j - 1].timestamp
            intervals.append(dt)
        }

        // Tempo: 70% of minimum observed interval (allow slightly faster than calibration pace)
        let computedTempo: Double
        if intervals.isEmpty {
            computedTempo = baseTempo
        } else {
            computedTempo = max(intervals.min()! * 0.7, 0.5)
        }

        // Convert to sensitivity multiplier
        let multiplier = computedThreshold / baseThreshold

        print("[Calibration] Analysis: \(ordered.count) reps, median peak=\(String(format: "%.3f", medianPeak)), threshold=\(String(format: "%.3f", computedThreshold)), multiplier=\(String(format: "%.2f", multiplier)), tempo=\(String(format: "%.1f", computedTempo))")

        return Result(
            sensitivityMultiplier: multiplier,
            tempo: computedTempo,
            peaksFound: ordered.count
        )
    }
}
