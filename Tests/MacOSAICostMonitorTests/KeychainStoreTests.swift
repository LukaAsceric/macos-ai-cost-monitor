import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class KeychainStoreTests: XCTestCase {
    func test_inMemoryStoreRoundTripsAndDeletes() throws {
        let store = InMemorySecretStore()

        XCTAssertNil(try store.read())
        try store.save("test-management-key")
        XCTAssertEqual(try store.read(), "test-management-key")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func test_keychainStoreUsesStableServiceAndAccount() {
        XCTAssertEqual(KeychainStore.service, "com.example.MacOSAICostMonitor")
        XCTAssertEqual(KeychainStore.account, "openrouter-management-key")
    }
}
