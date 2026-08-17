import Foundation
import Security

public protocol SecretStore: Sendable {
    func read() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

public enum KeychainStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)

    public var userMessage: String {
        "The OpenRouter key could not be read from Keychain."
    }
}

public final class KeychainStore: SecretStore, @unchecked Sendable {
    public static let service = "com.example.MacOSAICostMonitor"
    public static let account = "openrouter-management-key"

    private let service: String
    private let account: String

    public init(service: String = KeychainStore.service, account: String = KeychainStore.account) {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedStatus(errSecDecode)
        }
        return value
    }

    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
