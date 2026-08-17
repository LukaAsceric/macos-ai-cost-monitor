import Foundation
import LocalAuthentication
import Security

public protocol SecretStore: Sendable {
    func read() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}

public enum KeychainStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case authenticationRequired

    public var userMessage: String {
        switch self {
        case .authenticationRequired:
            return "Keychain authorization is required. Open the signed app bundle once, then try again."
        case .unexpectedStatus:
            return "The OpenRouter key could not be read from Keychain."
        }
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
        let query = Self.readQuery(service: service, account: account)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                throw KeychainStoreError.authenticationRequired
            }
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.unexpectedStatus(errSecDecode)
        }
        return value
    }

    internal static func readQuery(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return query
    }

    internal static func readQueryForTesting(service: String, account: String) -> [String: Any] {
        readQuery(service: service, account: account)
    }

    public func save(_ value: String) throws {
        let data = Data(value.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, updateAttributes as CFDictionary)
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
