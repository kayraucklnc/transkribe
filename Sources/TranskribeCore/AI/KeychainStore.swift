import Foundation
import Security

/// Stores secrets (like the Anthropic API key) as generic passwords in the user's keychain.
public struct KeychainStore: Sendable {
    public static let defaultService = IdentifierMigration.bundleIdentifier

    public struct KeychainError: LocalizedError, Equatable, Sendable {
        public var status: OSStatus

        public var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "Couldn't access the keychain: \(detail)"
        }
    }

    public let service: String
    /// Where the secret lived under the app's previous identifier; moved over on first read.
    public let legacyService: String?

    public init(service: String = KeychainStore.defaultService,
                legacyService: String? = IdentifierMigration.legacyBundleIdentifier) {
        self.service = service
        self.legacyService = legacyService == service ? nil : legacyService
    }

    public func get(account: String) -> String? {
        if let value = read(account: account) { return value }
        guard let legacyService else { return nil }
        let legacy = KeychainStore(service: legacyService, legacyService: nil)
        guard let value = legacy.read(account: account), (try? set(value, account: account)) != nil else { return nil }
        try? legacy.delete(account: account)
        return value
    }

    private func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(account: account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
