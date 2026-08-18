import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class UpdateConfigurationTests: XCTestCase {
    func test_requiresAppBundleFeedAndPublicKey() {
        XCTAssertFalse(UpdateConfiguration.isValid(
            bundleURL: URL(fileURLWithPath: "/tmp/.build/debug"),
            bundleIdentifier: nil,
            feedURLString: nil,
            publicKey: nil
        ))
        XCTAssertFalse(UpdateConfiguration.isValid(
            bundleURL: URL(fileURLWithPath: "/Applications/AI Cost Monitor.app"),
            bundleIdentifier: "com.lukaasceric.AICostMonitor",
            feedURLString: UpdateConfiguration.feedURL.absoluteString,
            publicKey: ""
        ))
        XCTAssertFalse(UpdateConfiguration.isValid(
            bundleURL: URL(fileURLWithPath: "/Applications/AI Cost Monitor.app"),
            bundleIdentifier: "com.lukaasceric.AICostMonitor",
            feedURLString: "http://updates.example.com/appcast.xml",
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        ))
        XCTAssertTrue(UpdateConfiguration.isValid(
            bundleURL: URL(fileURLWithPath: "/Applications/AI Cost Monitor.app"),
            bundleIdentifier: "com.lukaasceric.AICostMonitor",
            feedURLString: UpdateConfiguration.feedURL.absoluteString,
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        ))
    }
}

final class UpdateManagerTests: XCTestCase {
    @MainActor
    func test_unconfiguredDirectBinaryDoesNotCreateUpdater() {
        let manager = UpdateManager(
            bundleURL: URL(fileURLWithPath: "/tmp/.build/debug"),
            bundleIdentifier: nil,
            feedURLString: nil,
            publicKey: nil
        )

        XCTAssertFalse(manager.isConfigured)
        XCTAssertFalse(manager.canCheckForUpdates)
        XCTAssertFalse(manager.automaticUpdates)
    }
}
