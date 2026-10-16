import Foundation
import Security

/// Where Splark keeps tokens. Values are UTF-8 strings (JSON for structured credentials).
public protocol SecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public enum SecretStoreError: Error, Equatable { case keychain(OSStatus) }

/// Generic-password items in the login keychain, one per key, under a single service name.
public struct KeychainStore: SecretStore {
    public let service: String
    public init(service: String = "dev.splark.Splark") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    public func read(_ key: String) throws -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw SecretStoreError.keychain(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychain(status)
        }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}

/// Test double and preview store.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init(_ initial: [String: String] = [:]) { values = initial }
    public func read(_ key: String) throws -> String? { lock.withLock { values[key] } }
    public func write(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    public func delete(_ key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}
