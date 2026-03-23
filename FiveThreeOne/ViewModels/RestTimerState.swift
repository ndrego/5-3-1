import Foundation
import AudioToolbox
import UIKit
import AVFoundation

/// Timer alert sounds — uses the built-in iOS ringtones (same ones the Clock timer uses).
enum TimerSound: String, CaseIterable, Identifiable {
    case radar = "Radar"
    case apex = "Apex"
    case beacon = "Beacon"
    case bulletin = "Bulletin"
    case chimes = "Chimes"
    case circuit = "Circuit"
    case constellation = "Constellation"
    case cosmic = "Cosmic"
    case crystals = "Crystals"
    case hillside = "Hillside"
    case illuminate = "Illuminate"
    case nightOwl = "Night Owl"
    case opening = "Opening"
    case playtime = "Playtime"
    case presto = "Presto"
    case radiate = "Radiate"
    case ripples = "Ripples"
    case sencha = "Sencha"
    case signal = "Signal"
    case silk = "Silk"
    case slowRise = "Slow Rise"
    case stargaze = "Stargaze"
    case summit = "Summit"
    case twinkle = "Twinkle"
    case uplift = "Uplift"

    var id: String { rawValue }

    /// File name in /Library/Ringtones/
    var fileName: String {
        switch self {
        case .nightOwl: return "Night Owl.m4r"
        case .slowRise: return "Slow Rise.m4r"
        default: return "\(rawValue).m4r"
        }
    }

    var filePath: String {
        "/Library/Ringtones/\(fileName)"
    }
}

@MainActor @Observable
final class RestTimerState {
    var isRunning = false
    var totalSeconds: Int = 180
    var remainingSeconds: Int = 0
    var recovered = false
    var recoveryTargetHR: Int?
    var completedNaturally = false
    var selectedSound: TimerSound = .radar

    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?

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

    // MARK: - Sound Preview

    func previewSound(_ sound: TimerSound) {
        playSound(sound)
    }

    // MARK: - Alerts

    private func playAlert() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        playSound(selectedSound)
    }

    private func playRecoveryAlert() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        playSound(selectedSound)
    }

    private func playSound(_ sound: TimerSound) {
        // .playback plays through speaker even when silent switch is on
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let url = URL(fileURLWithPath: sound.filePath)
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            // Fallback for simulator or missing file
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            return
        }
        player.volume = 1.0
        player.play()
        audioPlayer = player
    }
}
