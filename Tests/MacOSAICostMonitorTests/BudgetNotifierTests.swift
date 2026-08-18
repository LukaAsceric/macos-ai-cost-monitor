import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class BudgetNotifierTests: XCTestCase {
    func test_directSwiftRunBundleDoesNotQualifyForUserNotifications() {
        let debugBinaryURL = URL(fileURLWithPath: "/Users/luka/dev/repos/project/.build/arm64-apple-macosx/debug/MacOSAICostMonitor")

        XCTAssertFalse(BudgetNotifier.isSupportedAppBundle(
            bundleURL: debugBinaryURL,
            bundleIdentifier: nil
        ))
    }

    func test_appBundleWithIdentifierQualifiesForUserNotifications() {
        let appURL = URL(fileURLWithPath: "/Applications/MacOSAICostMonitor.app")

        XCTAssertTrue(BudgetNotifier.isSupportedAppBundle(
            bundleURL: appURL,
            bundleIdentifier: "com.example.MacOSAICostMonitor"
        ))
    }

    func test_appBundleWithoutIdentifierDoesNotQualify() {
        let appURL = URL(fileURLWithPath: "/Applications/MacOSAICostMonitor.app")

        XCTAssertFalse(BudgetNotifier.isSupportedAppBundle(
            bundleURL: appURL,
            bundleIdentifier: nil
        ))
    }

    func test_formattedNotificationBodyRespectsDecimalPlaces() {
        let amount = Decimal(string: "12.34567")!
        let limit = Decimal(string: "10.0")!

        let body2Decimals = BudgetNotifier.formattedNotificationBody(amount: amount, limit: limit, decimalPlaces: 2)
        XCTAssertEqual(body2Decimals, "Spend $12.35 reached the configured budget of $10.00.")

        let body4Decimals = BudgetNotifier.formattedNotificationBody(amount: amount, limit: limit, decimalPlaces: 4)
        XCTAssertEqual(body4Decimals, "Spend $12.3457 reached the configured budget of $10.00.")
    }
}
