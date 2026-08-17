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
}
