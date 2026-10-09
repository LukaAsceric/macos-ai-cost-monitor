import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class SpendChartLayoutTests: XCTestCase {
    func test_xPositionsAreTimeProportional() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 4_000)

        XCTAssertEqual(SpendChartLayout.xPosition(date: start, start: start, end: end), 0.0)
        XCTAssertEqual(
            SpendChartLayout.xPosition(date: Date(timeIntervalSince1970: 2_500), start: start, end: end),
            0.5
        )
        XCTAssertEqual(SpendChartLayout.xPosition(date: end, start: start, end: end), 1.0)
    }

    func test_xPositionsClampOutsideTheWindow() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(
            SpendChartLayout.xPosition(date: Date(timeIntervalSince1970: 0), start: start, end: end),
            0.0
        )
        XCTAssertEqual(
            SpendChartLayout.xPosition(date: Date(timeIntervalSince1970: 9_000), start: start, end: end),
            1.0
        )
    }

    func test_xPositionsCenterOnDegenerateWindow() {
        let instant = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(SpendChartLayout.xPosition(date: instant, start: instant, end: instant), 0.5)
    }

    func test_yPositionMapsOntoTheScale() {
        let height: CGFloat = 100

        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "0")!, yMax: Decimal(string: "10")!, height: height),
            height
        )
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "5")!, yMax: Decimal(string: "10")!, height: height),
            height / 2
        )
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "10")!, yMax: Decimal(string: "10")!, height: height),
            0
        )
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "25")!, yMax: Decimal(string: "10")!, height: height),
            0
        )
    }

    func test_niceCeilingRoundsUpToReadableValues() {
        XCTAssertEqual(SpendChartLayout.niceCeiling(Decimal(string: "2.53")!), Decimal(string: "3")!)
        XCTAssertEqual(SpendChartLayout.niceCeiling(Decimal(string: "0.53")!), Decimal(string: "0.6")!)
        XCTAssertEqual(SpendChartLayout.niceCeiling(Decimal(string: "12.3")!), Decimal(string: "12.5")!)
        XCTAssertEqual(SpendChartLayout.niceCeiling(Decimal(string: "1000")!), Decimal(string: "1000")!)
        XCTAssertEqual(SpendChartLayout.niceCeiling(.zero), Decimal(string: "1")!)
    }

    func test_yTicksSplitTheScaleInHalves() {
        XCTAssertEqual(
            SpendChartLayout.yTicks(maxValue: Decimal(string: "1")!),
            [Decimal(string: "0")!, Decimal(string: "0.5")!, Decimal(string: "1")!]
        )
    }

    func test_xTicksIncludeBothEndpoints() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 4_000)

        let ticks = SpendChartLayout.xTicks(start: start, end: end, count: 4)

        XCTAssertEqual(ticks.map(\.timeIntervalSince1970), [1_000, 2_000, 3_000, 4_000])
    }

    func test_xTicksCollapseForSingleOrDegenerateRequests() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 4_000)

        XCTAssertEqual(SpendChartLayout.xTicks(start: start, end: end, count: 1), [start])
        XCTAssertEqual(SpendChartLayout.xTicks(start: start, end: start, count: 4), [start])
    }
}
