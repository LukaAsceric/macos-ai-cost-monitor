import Foundation
import XCTest
@testable import MacOSAICostMonitor

@MainActor
final class AppLogStoreTests: XCTestCase {
    func test_keepsEntriesBoundedAndCanClear() {
        let store = AppLogStore(capacity: 2, now: { Date(timeIntervalSince1970: 123) })

        store.info("first")
        store.warning("second")
        store.error("third")

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.map(\.message), ["second", "third"])

        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func test_redactsSecretsAndAuthorizationValues() {
        let store = AppLogStore()

        store.info("Authorization: Bearer secret-token")
        store.info("apiKey=sk-or-v1-abc123")
        store.info("password: hidden-value")

        let text = store.text()
        XCTAssertFalse(text.contains("secret-token"))
        XCTAssertFalse(text.contains("sk-or-v1-abc123"))
        XCTAssertFalse(text.contains("hidden-value"))
        XCTAssertEqual(text.components(separatedBy: "[REDACTED]").count - 1, 3)
    }

    func test_exportRedactsUntrustedLogEntries() {
        let raw = LogEntry(level: .error, message: "server said token=secret-value")
        XCTAssertFalse(raw.line.contains("secret-value"))
        XCTAssertFalse(AppLogStore.redactForExport(raw.message).contains("secret-value"))
    }

    func test_exportWritesRedactedFile() throws {
        let store = AppLogStore()
        store.info("token=secret-value")
        let model = CostMonitorModel(
            provider: FakeUsageProvider(),
            secretStore: InMemorySecretStore(),
            cache: InMemoryCostCache(),
            logStore: store
        )
        let url = try model.exportLogs()
        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("secret-value"))
        XCTAssertTrue(text.contains("[REDACTED]"))
    }

    func test_filtersByLevelInConsumer() {
        let store = AppLogStore()
        store.debug("details")
        store.info("request completed")
        store.error("request failed")

        let errors = store.entries.filter { $0.level == .error }
        XCTAssertEqual(errors.map(\.message), ["request failed"])
    }
}
