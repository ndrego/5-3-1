import SwiftUI

struct RestTimerView: View {
    @Bindable var timer: RestTimerState
    var currentHR: Double = 0

    var body: some View {
        if timer.isRunning {
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        timer.adjustTime(by: -15)
                    } label: {
                        Text("-15s")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)

                    VStack(spacing: 2) {
                        Text(timer.formattedRemaining)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(timerColor)

                        if timer.recovered {
                            Text("Recovered")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        } else if let target = timer.recoveryTargetHR {
                            Text("Target: \(target) BPM")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        timer.adjustTime(by: 15)
                    } label: {
                        Text("+15s")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        timer.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: timer.progress)
                    .tint(progressColor)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: currentHR) {
                timer.checkRecovery(currentHR: currentHR)
            }
        }
    }

    private var timerColor: Color {
        if timer.recovered { return .green }
        if timer.remainingSeconds <= 10 { return .orange }
        return .primary
    }

    private var progressColor: Color {
        if timer.recovered { return .green }
        if timer.remainingSeconds <= 10 { return .orange }
        return .blue
    }
}
