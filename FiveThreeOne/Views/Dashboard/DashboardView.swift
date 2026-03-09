import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Cycle.number, order: .reverse) private var cycles: [Cycle]
    @Query private var settings: [UserSettings]

    var currentCycle: Cycle? { cycles.first(where: { !$0.isComplete }) ?? cycles.first }
    var userSettings: UserSettings? { settings.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let cycle = currentCycle {
                        cycleOverview(cycle)
                        workoutCards(cycle)
                    } else {
                        ContentUnavailableView(
                            "No Active Cycle",
                            systemImage: "dumbbell",
                            description: Text("Set up your training maxes to get started.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("5/3/1")
        }
    }

    @ViewBuilder
    private func cycleOverview(_ cycle: Cycle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cycle \(cycle.number)")
                .font(.headline)
            Text(cycle.programVariant.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Lift.allCases) { lift in
                    HStack {
                        Text(lift.shortName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 36)
                        Spacer()
                        Text("\(Int(cycle.trainingMax(for: lift))) lbs")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .padding(8)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func workoutCards(_ cycle: Cycle) -> some View {
        ForEach(1...4, id: \.self) { week in
            VStack(alignment: .leading, spacing: 8) {
                Text("Week \(week) — \(ProgramEngine.weekLabel(week))")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(Lift.allCases) { lift in
                    NavigationLink {
                        WorkoutView(cycle: cycle, lift: lift, week: week)
                    } label: {
                        HStack {
                            Text(lift.displayName)
                                .font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
