import SwiftUI

/// A compact sparkline showing weight progression over recent workouts.
struct LiftSparklineView: View {
    let dataPoints: [(date: Date, weight: Double)]

    var body: some View {
        if dataPoints.count >= 2 {
            HStack(spacing: 4) {
                sparkline
                    .frame(width: 60, height: 24)

                // Latest weight label
                Text("\(Int(dataPoints.last!.weight))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sparkline: some View {
        let weights = dataPoints.map { $0.weight }
        let minW = weights.min() ?? 0
        let maxW = weights.max() ?? 1
        let range = max(maxW - minW, 1)

        return Canvas { context, size in
            let stepX = size.width / CGFloat(weights.count - 1)
            let points = weights.enumerated().map { i, w in
                CGPoint(
                    x: CGFloat(i) * stepX,
                    y: size.height - (CGFloat(w - minW) / CGFloat(range)) * size.height
                )
            }

            // Draw line
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(.orange), lineWidth: 1.5)

            // Draw dots
            for point in points {
                let dot = Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(.orange))
            }
        }
    }
}
