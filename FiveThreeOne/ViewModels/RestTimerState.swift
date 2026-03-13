import Foundation
import AudioToolbox
import UIKit

@Observable
final class RestTimerState {
    var isRunning = false
    var totalSeconds: Int = 180
    var remainingSeconds: Int = 0
    var recovered = false
    var recoveryTargetHR: Int?
    var completedNaturally = false

    private var timer: Timer?

    func start(seconds: Int, recoveryHR: Int? = nil) {
        stop()
        totalSeconds = seconds
        remainingSeconds = seconds
        recoveryTargetHR = recoveryHR
        recovered = false
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            } else {
                self.completedNaturally = true
                self.playAlert()
                self.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        remainingSeconds = 0
        recovered = false
        recoveryTargetHR = nil
    }

    func adjustTime(by delta: Int) {
        totalSeconds = max(0, totalSeconds + delta)
        remainingSeconds = max(0, remainingSeconds + delta)
    }

    /// Call with current HR each tick to check recovery
    func checkRecovery(currentHR: Double) {
        guard let target = recoveryTargetHR, !recovered else { return }
        if currentHR > 0 && currentHR <= Double(target) {
            recovered = true
            playRecoveryAlert()
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    var formattedRemaining: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Alerts

    private func playAlert() {
        AudioServicesPlaySystemSound(1007) // "Tink" — short, clear alert tone
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func playRecoveryAlert() {
        AudioServicesPlaySystemSound(1003) // Soft chime
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
