import Foundation
import SwiftUI

/// Pure, testable geometry helpers for the spend line chart. Kept free of
/// SwiftUI/AppKit so unit tests can exercise edge cases without rendering.
public enum SpendChartLayout {
    /// Horizontal position fraction (0...1) for a point at a given index.
    /// A single point is centered horizontally rather than pinned to the left edge.
    public static func xFraction(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0.5 }
        return CGFloat(index) / CGFloat(count - 1)
    }

    /// Top-based vertical position for a usage value against a maximum and a height.
    /// Clamped so outliers never draw outside the chart bounds.
    public static func yPosition(
        usage: Decimal,
        maxUsage: Decimal,
        height: CGFloat
    ) -> CGFloat {
        let ratio = NSDecimalNumber(decimal: usage).doubleValue
            / max(NSDecimalNumber(decimal: maxUsage).doubleValue, 0.0001)
        let clamped = min(max(ratio, 0), 1)
        return height - height * CGFloat(clamped)
    }
}

@MainActor
public struct SpendChartView: View {
    public let points: [CostSeriesPoint]

    public init(points: [CostSeriesPoint]) {
        self.points = points
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let maxValue = points.map(\.usage).max() ?? .zero

            ZStack {
                if !points.isEmpty {
                    areaPath(width: width, height: height, maxValue: maxValue)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                if points.count <= 1 {
                    if let point = points.first {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .position(
                                x: points.count == 1 ? width * 0.5 : 0,
                                y: SpendChartLayout.yPosition(usage: point.usage, maxUsage: maxValue, height: height)
                            )
                    }
                } else {
                    linePath(width: width, height: height, maxValue: maxValue)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
        .accessibilityLabel("Spend over the selected range")
    }

    private func linePath(width: CGFloat, height: CGFloat, maxValue: Decimal) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let x = SpendChartLayout.xFraction(index: index, count: points.count) * width
                let y = SpendChartLayout.yPosition(usage: point.usage, maxUsage: maxValue, height: height)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func areaPath(width: CGFloat, height: CGFloat, maxValue: Decimal) -> Path {
        Path { path in
            guard let first = points.first, points.count > 1 else { return }
            path.move(to: CGPoint(x: 0, y: height))
            for (index, point) in points.enumerated() {
                let x = SpendChartLayout.xFraction(index: index, count: points.count) * width
                let y = SpendChartLayout.yPosition(usage: point.usage, maxUsage: maxValue, height: height)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
    }
}