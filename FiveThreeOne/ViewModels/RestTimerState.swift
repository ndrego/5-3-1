import Foundation

@Observable
final class RestTimerState {
    var isRunning = false
    var totalSeconds: Int = 180
    var remainingSeconds: Int = 0

    private var timer: Timer?

    func start(seconds: Int) {
        stop()
        totalSeconds = seconds
        remainingSeconds = seconds
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remainingSeconds > 0 {
                self.remainingSeconds -= 1
            } else {
                self.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        remainingSeconds = 0
    }

    func adjustTime(by delta: Int) {
        totalSeconds = max(0, totalSeconds + delta)
        remainingSeconds = max(0, remainingSeconds + delta)
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
}
