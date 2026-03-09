import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    let exerciseName: String
    @Query(sort: \CompletedWorkout.date, order: .reverse) private var workouts: [CompletedWorkout]

    @State private var selectedTab = 0

    private var performances: [(date: Date, performance: ExercisePerformance)] {
        workouts.compactMap { workout in
            guard let perf = workout.allExercisePerformances.first(where: {
                $0.exerciseName == exerciseName
            }) else { return nil }
            return (date: workout.date, performance: perf)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("History").tag(0)
                Text("Charts").tag(1)
                Text("Records").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case 0: historyTab
            case 1: chartsTab
            case 2: recordsTab
            default: EmptyView()
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - History Tab

    private var historyTab: some View {
        Group {
            if performances.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock",
                    description: Text("Complete a workout with this exercise to see history."))
            } else {
                List {
                    ForEach(performances, id: \.date) { entry in
                        historyRow(date: entry.date, perf: entry.performance)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func historyRow(date: Date, perf: ExercisePerformance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date, style: .date)
                .font(.subheadline)
                .fontWeight(.semibold)

            let workingSets = perf.sets.filter { $0.isComplete && $0.setType != .warmup }
            ForEach(Array(workingSets.enumerated()), id: \.offset) { _, set in
                HStack(spacing: 4) {
                    Text("\(Int(set.weight)) lbs")
                        .monospacedDigit()
                    Text("×")
                    Text("\(set.actualReps)\(set.isAMRAP ? "+" : "")")
                        .monospacedDigit()
                        .fontWeight(set.isAMRAP ? .bold : .regular)
                    if set.isAMRAP {
                        let e1rm = set.weight * (1 + Double(set.actualReps) / 30.0)
                        Text("E1RM \(Int(e1rm))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if perf.totalVolume > 0 {
                    Label("\(formatVolume(perf.totalVolume))", systemImage: "scalemass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if perf.completedWorkingSets > 0 {
                    Text("\(perf.completedWorkingSets) sets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Charts Tab

    private var chartsTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                if performances.count >= 2 {
                    chartSection(
                        title: "Top Set Weight",
                        data: performances.reversed().compactMap { entry in
                            guard let best = entry.performance.bestSet else { return nil }
                            return (date: entry.date, value: best.weight)
                        },
                        color: .orange,
                        unit: "lbs"
                    )

                    chartSection(
                        title: "Volume",
                        data: performances.reversed().map {
                            (date: $0.date, value: $0.performance.totalVolume)
                        },
                        color: .blue,
                        unit: "lbs"
                    )

                    let e1rmData: [(date: Date, value: Double)] = performances.reversed().compactMap { entry in
                        guard let best = entry.performance.bestSet, best.actualReps > 0 else { return nil }
                        let e1rm = best.weight * (1 + Double(best.actualReps) / 30.0)
                        return (date: entry.date, value: e1rm)
                    }
                    if e1rmData.count >= 2 {
                        chartSection(
                            title: "Estimated 1RM",
                            data: e1rmData,
                            color: .green,
                            unit: "lbs"
                        )
                    }

                    chartSection(
                        title: "Total Reps",
                        data: performances.reversed().map {
                            (date: $0.date, value: Double($0.performance.totalReps))
                        },
                        color: .purple,
                        unit: ""
                    )
                } else {
                    ContentUnavailableView("Not Enough Data", systemImage: "chart.xyaxis.line",
                        description: Text("Need at least 2 sessions to show charts."))
                }
            }
            .padding()
        }
    }

    private func chartSection(title: String, data: [(date: Date, value: Double)], color: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let latest = data.last {
                    Text("\(Int(latest.value))\(unit.isEmpty ? "" : " \(unit)")")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                }
            }

            chartCanvas(data: data, color: color)
                .frame(height: 120)

            // Date range
            if let first = data.first, let last = data.last, data.count > 1 {
                HStack {
                    Text(first.date, style: .date)
                    Spacer()
                    Text(last.date, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chartCanvas(data: [(date: Date, value: Double)], color: Color) -> some View {
        let values = data.map { $0.value }
        let minV = (values.min() ?? 0) * 0.95
        let maxV = (values.max() ?? 1) * 1.05
        let range = max(maxV - minV, 1)

        return Canvas { context, size in
            guard values.count >= 2 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { i, v in
                CGPoint(
                    x: CGFloat(i) * stepX,
                    y: size.height - (CGFloat(v - minV) / CGFloat(range)) * size.height
                )
            }

            // Fill under line
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: points[0].x, y: size.height))
            for point in points {
                fillPath.addLine(to: point)
            }
            fillPath.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(color.opacity(0.1)))

            // Line
            var linePath = Path()
            linePath.move(to: points[0])
            for point in points.dropFirst() {
                linePath.addLine(to: point)
            }
            context.stroke(linePath, with: .color(color), lineWidth: 2)

            // Dots
            for point in points {
                let dot = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(color))
            }
        }
    }

    // MARK: - Records Tab

    private var recordsTab: some View {
        let allSets = performances.flatMap { entry in
            entry.performance.sets
                .filter { $0.isComplete && $0.setType != .warmup }
                .map { (date: entry.date, set: $0) }
        }

        return Group {
            if allSets.isEmpty {
                ContentUnavailableView("No Records", systemImage: "trophy",
                    description: Text("Complete a workout with this exercise to see records."))
            } else {
                List {
                    // Heaviest weight
                    if let heaviest = allSets.max(by: { $0.set.weight < $1.set.weight }) {
                        recordRow(
                            title: "Heaviest Weight",
                            value: "\(Int(heaviest.set.weight)) lbs × \(heaviest.set.actualReps)",
                            date: heaviest.date,
                            icon: "scalemass.fill",
                            color: .orange
                        )
                    }

                    // Best estimated 1RM
                    let e1rms = allSets.filter { $0.set.actualReps > 0 }.map { entry in
                        let e1rm = entry.set.weight * (1 + Double(entry.set.actualReps) / 30.0)
                        return (date: entry.date, set: entry.set, e1rm: e1rm)
                    }
                    if let bestE1RM = e1rms.max(by: { $0.e1rm < $1.e1rm }) {
                        recordRow(
                            title: "Best Estimated 1RM",
                            value: "\(Int(bestE1RM.e1rm)) lbs (\(Int(bestE1RM.set.weight)) × \(bestE1RM.set.actualReps))",
                            date: bestE1RM.date,
                            icon: "trophy.fill",
                            color: .yellow
                        )
                    }

                    // Most reps at any weight
                    if let mostReps = allSets.max(by: { $0.set.actualReps < $1.set.actualReps }) {
                        recordRow(
                            title: "Most Reps",
                            value: "\(mostReps.set.actualReps) reps at \(Int(mostReps.set.weight)) lbs",
                            date: mostReps.date,
                            icon: "repeat",
                            color: .green
                        )
                    }

                    // Highest single-session volume
                    if let bestVolume = performances.max(by: { $0.performance.totalVolume < $1.performance.totalVolume }) {
                        recordRow(
                            title: "Best Session Volume",
                            value: formatVolume(bestVolume.performance.totalVolume) + " lbs",
                            date: bestVolume.date,
                            icon: "chart.bar.fill",
                            color: .blue
                        )
                    }

                    // Most sets in a session
                    if let mostSets = performances.max(by: {
                        $0.performance.completedWorkingSets < $1.performance.completedWorkingSets
                    }) {
                        recordRow(
                            title: "Most Sets",
                            value: "\(mostSets.performance.completedWorkingSets) working sets",
                            date: mostSets.date,
                            icon: "list.number",
                            color: .purple
                        )
                    }

                    // Weight PRs by rep count (1RM, 3RM, 5RM, etc.)
                    Section("Weight PRs by Rep Count") {
                        let repCounts = [1, 2, 3, 5, 8, 10]
                        ForEach(repCounts, id: \.self) { targetReps in
                            let qualifying = allSets.filter { $0.set.actualReps >= targetReps }
                            if let best = qualifying.max(by: { $0.set.weight < $1.set.weight }) {
                                HStack {
                                    Text("\(targetReps)RM")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(width: 40, alignment: .leading)
                                    Text("\(Int(best.set.weight)) lbs")
                                        .monospacedDigit()
                                    if best.set.actualReps > targetReps {
                                        Text("(\(best.set.actualReps) reps)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(best.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func recordRow(title: String, value: String, date: Date, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Spacer()
            Text(date, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func formatVolume(_ vol: Double) -> String {
        if vol >= 1000 {
            return String(format: "%.1fk", vol / 1000)
        }
        return "\(Int(vol))"
    }
}
