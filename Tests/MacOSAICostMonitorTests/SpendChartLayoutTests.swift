import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class SpendChartLayoutTests: XCTestCase {
    func test_xFraction_spreadsAcrossFullWidth() {
        XCTAssertEqual(SpendChartLayout.xFraction(index: 0, count: 3), 0.0)
        XCTAssertEqual(SpendChartLayout.xFraction(index: 1, count: 3), 0.5)
        XCTAssertEqual(SpendChartLayout.xFraction(index: 2, count: 3), 1.0)
    }

    func test_xFraction_singlePointIsCentered() {
        XCTAssertEqual(SpendChartLayout.xFraction(index: 0, count: 1), 0.5)
    }

    func test_yPosition_placesZeroAtBaseline() {
        let height: CGFloat = 100
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "0")!, maxUsage: Decimal(string: "10")!, height: height),
            100
        )
    }

    func test_yPosition_placesMaxAtTop() {
        let height: CGFloat = 100
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "10")!, maxUsage: Decimal(string: "10")!, height: height),
            0
        )
    }

    func test_yPosition_midValueScalesLinearly() {
        let height: CGFloat = 100
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "5")!, maxUsage: Decimal(string: "10")!, height: height),
            50
        )
    }

    func test_yPosition_clampsOutlierAboveMax() {
        let height: CGFloat = 100
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "99")!, maxUsage: Decimal(string: "10")!, height: height),
            0
        )
    }

    func test_yPosition_clampsNegativeUsageToBaseline() {
        let height: CGFloat = 100
        XCTAssertEqual(
            SpendChartLayout.yPosition(usage: Decimal(string: "-4")!, maxUsage: Decimal(string: "10")!, height: height),
            100
        )
    }
}