// Sources/ClaudeStatusBarCore/Storage/KeychainTokenStore.swift
import Foundation
import Security

public enum KeychainError: Error, Equatable { case status(OSStatus) }

public struct KeychainTokenStore: TokenStore {
    private let service: String
    public init(service: String) { self.service = service }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func save(_ bundle: TokenBundle, for id: UUID) throws {
        let data = try JSONEncoder().encode(bundle)
        try delete(id)
        var q = baseQuery(id)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func load(_ id: UUID) throws -> TokenBundle? {
        var q = baseQuery(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(TokenBundle.self, from: data)
    }

    public func delete(_ id: UUID) throws {
        let status = SecItemDelete(baseQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
