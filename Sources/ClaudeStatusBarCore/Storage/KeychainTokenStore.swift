// Sources/ClaudeStatusBarCore/Storage/KeychainTokenStore.swift
import Foundation
import Security

public enum KeychainError: Error, Equatable { case status(OSStatus) }

protocol KeychainWriting: Sendable {
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
}

private struct SystemKeychainWriting: KeychainWriting {
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let lock = NSRecursiveLock()
    private let writes: any KeychainWriting
    public init(service: String) { self.service = service; self.writes = SystemKeychainWriting() }
    init(service: String, writes: any KeychainWriting) {
        self.service = service; self.writes = writes
    }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func save(_ bundle: TokenBundle, for id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(bundle)
        let query = baseQuery(id)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = writes.update(query, attributes: attributes)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            status = writes.add(item)
            if status == errSecDuplicateItem {
                // Jiný zápis mohl položku vytvořit mezi update a add.
                status = writes.update(query, attributes: attributes)
            }
        }
        // Při chybě nikdy nemažeme původní grant.
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func load(_ id: UUID) throws -> TokenBundle? {
        lock.lock(); defer { lock.unlock() }
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

    public func replace(_ bundle: TokenBundle, for id: UUID, matching previous: TokenBundle?) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard try load(id) == previous else { return false }
        try save(bundle, for: id)
        return true
    }

    public func delete(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(baseQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
