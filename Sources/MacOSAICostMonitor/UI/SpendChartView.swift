import Foundation
import SwiftUI

/// Pure, testable geometry helpers for the spend line chart. Kept free of
/// SwiftUI/AppKit so unit tests can exercise edge cases without rendering.
public enum SpendChartLayout {
    /// Horizontal fraction (0...1) for a date within the window, clamped to the
    /// edges. A degenerate window centers the point.
    public static func xPosition(date: Date, start: Date, end: Date) -> CGFloat {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0.5 }
        let fraction = date.timeIntervalSince(start) / span
        return CGFloat(min(max(fraction, 0), 1))
    }

    /// Top-based vertical position for a value on a 0...yMax scale and a height.
    /// Clamped so outliers never draw outside the chart bounds.
    public static func yPosition(
        usage: Decimal,
        yMax: Decimal,
        height: CGFloat
    ) -> CGFloat {
        let ratio = NSDecimalNumber(decimal: usage).doubleValue
            / max(NSDecimalNumber(decimal: yMax).doubleValue, 0.0001)
        let clamped = min(max(ratio, 0), 1)
        return height - height * CGFloat(clamped)
    }

    /// Rounds a maximum value up to a readable axis ceiling (e.g. 2.53 -> 3,
    /// 0.53 -> 0.6). Zero and negative maxima get a placeholder scale so the
    /// axis still renders.
    public static func niceCeiling(_ value: Decimal) -> Decimal {
        let v = NSDecimalNumber(decimal: value).doubleValue
        guard v > 0 else { return 1 }
        let magnitude = pow(10.0, floor(log10(v)))
        let mantissa = v / magnitude
        let candidates: [Double] = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
        let nice = candidates.first { $0 >= mantissa - 1e-9 } ?? 10
        return Decimal(string: String(format: "%.10g", nice * magnitude)) ?? 1
    }

    /// Y axis ticks for a nice ceiling: zero, the half, and the ceiling.
    public static func yTicks(maxValue: Decimal) -> [Decimal] {
        [0, maxValue / 2, maxValue]
    }

    /// Tick dates across the window, including both endpoints.
    public static func xTicks(start: Date, end: Date, count: Int) -> [Date] {
        guard count >= 2 else { return [start] }
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return [start] }
        return (0..<count).map { start.addingTimeInterval(span * Double($0) / Double(count - 1)) }
    }
}

/// Spend-over-time chart with real axes: the Y axis is US dollars per time
/// bucket (grid lines at zero, the half, and the axis ceiling) and the X axis
/// is time in the display time zone (clock times for short spans, dates for
/// longer ones).
@MainActor
public struct SpendChartView: View {
    public let points: [CostSeriesPoint]
    public let timeZone: TimeZone

    public init(points: [CostSeriesPoint], timeZone: TimeZone = .autoupdatingCurrent) {
        self.points = points
        self.timeZone = timeZone
    }

    private static let yAxisWidth: CGFloat = 40
    private static let xAxisHeight: CGFloat = 14

    public var body: some View {
        GeometryReader { proxy in
            let chartWidth = max(proxy.size.width - Self.yAxisWidth, 1)
            let chartHeight = max(proxy.size.height - Self.xAxisHeight, 1)
            let maxValue = points.map(\.usage).max() ?? .zero
            let yMax = SpendChartLayout.niceCeiling(maxValue)
            let window = dateWindow
            ZStack(alignment: .topLeading) {
                ForEach(Array(SpendChartLayout.yTicks(maxValue: yMax).enumerated()), id: \.offset) { _, tick in
                    let y = SpendChartLayout.yPosition(usage: tick, yMax: yMax, height: chartHeight)
                    Path { line in
                        line.move(to: CGPoint(x: Self.yAxisWidth, y: y))
                        line.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(Color.secondary.opacity(tick == 0 ? 0.3 : 0.12), lineWidth: 1)
                    Text(CostFormatStyle.headline(tick, maximumFractionDigits: 2))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.yAxisWidth - 8, alignment: .trailing)
                        .position(x: (Self.yAxisWidth - 8) / 2, y: min(max(y, 7), chartHeight - 7))
                }
                ForEach(Array(SpendChartLayout.xTicks(start: window.start, end: window.end, count: 4).enumerated()), id: \.offset) { _, tick in
                    let x = Self.yAxisWidth + SpendChartLayout.xPosition(date: tick, start: window.start, end: window.end) * chartWidth
                    Path { line in
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: chartHeight))
                    }
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    Text(timeLabel(tick, span: window.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: min(max(x, 18), proxy.size.width - 18), y: chartHeight + Self.xAxisHeight / 2)
                }
                if !points.isEmpty {
                    areaPath(yMax: yMax, window: window, chartWidth: chartWidth, chartHeight: chartHeight)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    if points.count > 1 {
                        linePath(yMax: yMax, window: window, chartWidth: chartWidth, chartHeight: chartHeight)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    } else if let point = points.first {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .position(
                                x: Self.yAxisWidth + SpendChartLayout.xPosition(date: point.date, start: window.start, end: window.end) * chartWidth,
                                y: SpendChartLayout.yPosition(usage: point.usage, yMax: yMax, height: chartHeight)
                            )
                    }
                }
            }
        }
        .accessibilityLabel("Spend per time bucket in US dollars over the selected range")
    }

    /// Time window covered by the points; a single point gets a small window
    /// around itself so the time axis still reads sensibly.
    private var dateWindow: DateInterval {
        guard let first = points.first?.date else {
            return DateInterval(start: Date(timeIntervalSince1970: 0), duration: 3600)
        }
        guard let last = points.last?.date, last > first else {
            return DateInterval(start: first.addingTimeInterval(-1800), duration: 3600)
        }
        return DateInterval(start: first, end: last)
    }

    private func linePath(yMax: Decimal, window: DateInterval, chartWidth: CGFloat, chartHeight: CGFloat) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let x = Self.yAxisWidth + SpendChartLayout.xPosition(date: point.date, start: window.start, end: window.end) * chartWidth
                let y = SpendChartLayout.yPosition(usage: point.usage, yMax: yMax, height: chartHeight)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func areaPath(yMax: Decimal, window: DateInterval, chartWidth: CGFloat, chartHeight: CGFloat) -> Path {
        Path { path in
            guard points.count > 1 else { return }
            path.move(to: CGPoint(x: Self.yAxisWidth, y: chartHeight))
            for point in points {
                let x = Self.yAxisWidth + SpendChartLayout.xPosition(date: point.date, start: window.start, end: window.end) * chartWidth
                let y = SpendChartLayout.yPosition(usage: point.usage, yMax: yMax, height: chartHeight)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: Self.yAxisWidth + chartWidth, y: chartHeight))
            path.closeSubpath()
        }
    }

    /// Time axis labels: clock times for short spans, dates beyond that.
    private func timeLabel(_ date: Date, span: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        if span <= 3 * 86_400 {
            formatter.dateFormat = "HH:mm"
        } else if span <= 180 * 86_400 {
            formatter.dateFormat = "dd.MM."
        } else {
            formatter.dateFormat = "MM.yy"
        }
        return formatter.string(from: date)
    }
}
