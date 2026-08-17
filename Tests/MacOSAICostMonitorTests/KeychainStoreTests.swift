import Foundation
import LocalAuthentication
import Security
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

    func test_readQueryDisallowsInteractiveAuthentication() {
        let query = KeychainStore.readQueryForTesting(
            service: KeychainStore.service,
            account: KeychainStore.account
        )
        let context = query[kSecUseAuthenticationContext as String] as? LAContext

        XCTAssertNotNil(context)
        XCTAssertTrue(context?.interactionNotAllowed == true)
        XCTAssertNil(query[kSecUseAuthenticationUI as String])
    }
}
