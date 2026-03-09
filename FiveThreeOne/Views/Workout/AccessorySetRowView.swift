import SwiftUI

struct AccessorySetRowView: View {
    let setNumber: Int
    @Binding var completed: CompletedSet
    var previousSet: CompletedSet?

    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(setNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Weight input
            VStack(alignment: .leading, spacing: 1) {
                TextField(previousWeightPlaceholder, value: $completed.weight, format: .number)
                    .font(.body)
                    .fontWeight(.medium)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .frame(width: 70)
                    .padding(6)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused($weightFocused)
                Text("lbs")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Reps input
            VStack(alignment: .leading, spacing: 1) {
                TextField(previousRepsPlaceholder, value: $completed.actualReps, format: .number)
                    .font(.body)
                    .fontWeight(.medium)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .frame(width: 50)
                    .padding(6)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused($repsFocused)
                Text("reps")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Complete toggle
            Button {
                if completed.isComplete {
                    completed.actualReps = 0
                } else if completed.actualReps == 0 {
                    completed.actualReps = completed.targetReps > 0 ? completed.targetReps : (previousSet?.actualReps ?? 10)
                }
                weightFocused = false
                repsFocused = false
            } label: {
                Image(systemName: completed.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(completed.isComplete ? .green : .secondary)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(completed.isComplete ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var previousWeightPlaceholder: String {
        if let prev = previousSet { return "\(Int(prev.weight))" }
        return "0"
    }

    private var previousRepsPlaceholder: String {
        if let prev = previousSet { return "\(prev.actualReps)" }
        return "0"
    }
}
