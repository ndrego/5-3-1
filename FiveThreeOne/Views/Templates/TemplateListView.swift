import SwiftUI
import SwiftData

struct TemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutTemplate.sortOrder) private var templates: [WorkoutTemplate]
    @Query(sort: \Cycle.number, order: .reverse) private var cycles: [Cycle]
    @Query private var settings: [UserSettings]

    @State private var selectedWeek: Int = 1
    @State private var showingNewTemplate = false
    @State private var selectedTemplate: WorkoutTemplate?

    private var currentCycle: Cycle? {
        cycles.first(where: { !$0.isComplete }) ?? cycles.first
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weekPicker
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Create a workout template to get started.")
                    )
                } else {
                    Section {
                        ForEach(templates) { template in
                            Button {
                                selectedTemplate = template
                            } label: {
                                templateCardContent(template)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(template)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Workout")
            .navigationDestination(item: $selectedTemplate) { template in
                TemplateWorkoutView(
                    template: template,
                    cycle: currentCycle,
                    week: selectedWeek
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewTemplate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTemplate) {
                NavigationStack {
                    TemplateEditView(template: nil)
                }
            }
            .onAppear {
                if templates.isEmpty {
                    WorkoutTemplate.seedDefaults(in: modelContext)
                }
            }
        }
    }

    // MARK: - Week Picker

    private var weekPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cycle = currentCycle {
                Text("Cycle \(cycle.number) — \(cycle.programVariant.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Week", selection: $selectedWeek) {
                ForEach(1...4, id: \.self) { week in
                    Text(ProgramEngine.weekLabel(week)).tag(week)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
    }

    // MARK: - Template Card Content

    private func templateCardContent(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name)
                .font(.headline)
                .foregroundStyle(.primary)

            FlowLayout(spacing: 6) {
                ForEach(template.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })) { entry in
                    Text(entry.exerciseName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(entry.isMainLift ? Color.blue.opacity(0.2) : Color(.tertiarySystemFill))
                        .foregroundStyle(entry.isMainLift ? .blue : .secondary)
                        .clipShape(Capsule())
                }
            }

            if let cycle = currentCycle {
                HStack(spacing: 12) {
                    ForEach(template.mainLifts, id: \.self) { lift in
                        let tm = cycle.trainingMax(for: lift)
                        let topSet = ProgramEngine.mainSets(
                            trainingMax: tm, week: selectedWeek,
                            variant: cycle.programVariant,
                            roundTo: settings.first?.roundTo ?? 5.0
                        ).last
                        if let topSet {
                            HStack(spacing: 4) {
                                Text(lift.shortName)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                Text("\(Int(topSet.weight))×\(topSet.reps)\(topSet.isAMRAP ? "+" : "")")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Simple flow layout for tag-like views
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
