import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class CostFormatStyleTests: XCTestCase {
    func test_formatsZeroAsCurrency() {
        XCTAssertEqual(CostFormatStyle.headline(.zero), "$0.00")
    }

    func test_preservesPrecisionForSubCentCosts() {
        XCTAssertEqual(CostFormatStyle.headline(Decimal(string: "0.0042")!), "$0.0042")
    }

    func test_formatsTokenCountsWithGrouping() {
        XCTAssertEqual(CostFormatStyle.tokens(1234567), "1,234,567")
    }
}
