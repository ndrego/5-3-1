import SwiftUI

struct SetRowView: View {
    let planned: ProgramEngine.PlannedSet
    @Binding var completed: CompletedSet
    let barWeight: Double
    let availablePlates: [Double]

    @State private var showPlates = false

    private var plateResult: PlateCalculator.PlateResult {
        PlateCalculator.calculate(
            totalWeight: planned.weight,
            barWeight: barWeight,
            availablePlates: availablePlates
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                // Set info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(Int(planned.weight)) lbs")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        if planned.isAMRAP {
                            Text("AMRAP")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(Int(planned.percentage * 100))% × \(planned.reps)\(planned.isAMRAP ? "+" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Plate info (compact)
                Button {
                    showPlates.toggle()
                } label: {
                    Text(plateResult.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Rep input
                repInput
            }
            .padding()
            .background(completed.isComplete ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if showPlates {
                PlateVisualView(plateResult: plateResult)
                    .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var repInput: some View {
        if planned.isAMRAP {
            // AMRAP: stepper-style input
            HStack(spacing: 8) {
                Button {
                    if completed.actualReps > 0 {
                        completed.actualReps -= 1
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }

                Text("\(completed.actualReps)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .frame(minWidth: 36)

                Button {
                    completed.actualReps += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        } else {
            // Standard set: tap to mark complete
            Button {
                completed.actualReps = completed.actualReps > 0 ? 0 : planned.reps
            } label: {
                Image(systemName: completed.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(completed.isComplete ? .green : .secondary)
            }
        }
    }
}

struct PlateVisualView: View {
    let plateResult: PlateCalculator.PlateResult

    var body: some View {
        if plateResult.plates.isEmpty {
            Text("Empty bar")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(plateResult.plates.enumerated()), id: \.offset) { _, plate in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(plateColor(plate))
                        .frame(width: plateWidth(plate), height: plateHeight(plate))
                        .overlay {
                            Text(formatPlate(plate))
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                        }
                }
                // Bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(.gray)
                    .frame(width: 40, height: 8)
            }
        }
    }

    private func plateColor(_ weight: Double) -> Color {
        switch weight {
        case 45: return .red
        case 35: return .blue
        case 25: return .green
        case 10: return .yellow
        case 5: return .orange
        case 2.5: return .purple
        default: return .gray
        }
    }

    private func plateWidth(_ weight: Double) -> CGFloat {
        max(16, CGFloat(weight) / 3.0 + 8)
    }

    private func plateHeight(_ weight: Double) -> CGFloat {
        switch weight {
        case 45: return 40
        case 35: return 36
        case 25: return 32
        case 10: return 26
        case 5: return 22
        case 2.5: return 18
        default: return 24
        }
    }

    private func formatPlate(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}
