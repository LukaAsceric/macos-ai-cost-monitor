import SwiftUI

@MainActor
public struct SpendChartView: View {
    public let points: [CostSeriesPoint]

    public init(points: [CostSeriesPoint]) {
        self.points = points
    }

    public var body: some View {
        GeometryReader { proxy in
            let maxValue = points.map(\.usage).max() ?? 1
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(points.count, 1)
            Path { path in
                for (index, point) in points.enumerated() {
                    let x = width * CGFloat(index) / CGFloat(max(count - 1, 1))
                    let ratio = NSDecimalNumber(decimal: point.usage).doubleValue / max(NSDecimalNumber(decimal: maxValue).doubleValue, 0.0001)
                    let y = height - (height * CGFloat(ratio))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .accessibilityLabel("Spend over the selected range")
    }
}
