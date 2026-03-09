import SwiftUI

struct RestTimerView: View {
    @Bindable var timer: RestTimerState

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

                    Text(timer.formattedRemaining)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(timer.remainingSeconds <= 10 ? .orange : .primary)

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
                    .tint(timer.remainingSeconds <= 10 ? .orange : .blue)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
