import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class CostFormatStyleTests: XCTestCase {
    func test_formatsZeroAsCurrency() {
        XCTAssertEqual(CostFormatStyle.headline(.zero, maximumFractionDigits: 2), "$0.00")
    }

    func test_preservesPrecisionForSubCentCosts() {
        XCTAssertEqual(CostFormatStyle.headline(Decimal(string: "0.0042")!, maximumFractionDigits: 4), "$0.0042")
    }

    func test_formatsTokenCountsWithGrouping() {
        XCTAssertEqual(CostFormatStyle.tokens(1234567), "1,234,567")
    }

    func test_respectsConfiguredMaximumDecimals() {
        XCTAssertEqual(CostFormatStyle.headline(Decimal(string: "1.23456789")!, maximumFractionDigits: 3), "$1.235")
    }
}
