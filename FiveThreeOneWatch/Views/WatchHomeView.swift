import SwiftUI

struct WatchHomeView: View {
    var connectivity: WatchConnectivityManager
    var workoutManager: WatchWorkoutManager
    var repCountingManager: RepCountingManager

    var body: some View {
        Group {
            if workoutManager.workoutActive {
                workoutView
            } else {
                waitingView
            }
        }
        .task {
            await workoutManager.requestHRAuthorization()
        }
    }

    // MARK: - Waiting

    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("531")
                .font(.headline)

            if connectivity.isPhoneReachable {
                Text("Connected")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("Waiting for phone…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Workout

    private var workoutView: some View {
        TabView {
            // Tab 1: Current set info + timer
            mainTab
            // Tab 2: Heart rate
            heartRateTab
            // Tab 3: End workout
            endWorkoutTab
        }
        .tabViewStyle(.verticalPage)
    }

    private var mainTab: some View {
        VStack(spacing: 6) {
            if workoutManager.timerRunning {
                timerView
            } else if !workoutManager.currentExercise.isEmpty {
                currentSetView
            } else {
                // No exercise context yet — show HR prominently
                if workoutManager.currentHR > 0 {
                    VStack(spacing: 4) {
                        Text("Workout Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("\(Int(workoutManager.currentHR))")
                                .font(.title)
                                .fontWeight(.bold)
                                .monospacedDigit()
                            Text("BPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Workout Active")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Current Set

    private var currentSetView: some View {
        VStack(spacing: 6) {
            Text(workoutManager.currentExercise)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if workoutManager.currentWeight > 0 {
                Text("\(workoutManager.formattedWeight) lbs")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            HStack(spacing: 4) {
                Text("\(workoutManager.currentTargetReps)\(workoutManager.currentIsAMRAP ? "+" : "") reps")
                    .font(.body)
                    .fontWeight(.medium)
                if repCountingManager.isActive {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(repCountingManager.repCount)")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }

            // Progress
            if workoutManager.currentTotalSets > 0 {
                Text("Set \(workoutManager.currentSetNumber) of \(workoutManager.currentTotalSets)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Complete set button
            Button {
                connectivity.sendCompleteSet()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // Inline HR
            if workoutManager.currentHR > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text("\(Int(workoutManager.currentHR))")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Timer

    private var timerView: some View {
        VStack(spacing: 4) {
            // Exercise context above timer
            if !workoutManager.currentExercise.isEmpty {
                Text(workoutManager.currentExercise)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: workoutManager.timerProgress)
                    .stroke(
                        workoutManager.recovered ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text(workoutManager.formattedRemaining)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(workoutManager.recovered ? .green : .primary)

                    if workoutManager.recovered {
                        Text("Recovered")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else if let target = workoutManager.recoveryTargetHR {
                        Text("→ \(target) BPM")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    // Show current HR inside ring
                    if workoutManager.currentHR > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                            Text("\(Int(workoutManager.currentHR))")
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(width: 110, height: 110)

            HStack(spacing: 12) {
                // Stop timer
                Button {
                    connectivity.sendStopTimer()
                    workoutManager.stopTimer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)

                // Progress
                if workoutManager.currentTotalSets > 0 {
                    Text("Set \(workoutManager.setsCompleted)/\(workoutManager.currentTotalSets)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Heart Rate Tab

    private var heartRateTab: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(.red)

            if workoutManager.currentHR > 0 {
                Text("\(Int(workoutManager.currentHR))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No HR data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let target = workoutManager.recoveryTargetHR {
                Divider()
                Text("Recovery: \(target) BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - End Workout

    private var endWorkoutTab: some View {
        VStack(spacing: 12) {
            Text("End Workout?")
                .font(.headline)

            Button(role: .destructive) {
                workoutManager.workoutActive = false
                workoutManager.stopTimer()
                workoutManager.stopWorkoutSession()
                connectivity.sendStopTimer()
            } label: {
                Label("End", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
