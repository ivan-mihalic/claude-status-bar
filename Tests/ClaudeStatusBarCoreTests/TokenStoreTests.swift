// Tests/ClaudeStatusBarCoreTests/TokenStoreTests.swift
import Testing
import Foundation
import Security
@testable import ClaudeStatusBarCore

private func sample() -> TokenBundle {
    TokenBundle(accessToken: "AT", refreshToken: "RT",
                expiresAt: .init(timeIntervalSince1970: 123), scopes: ["user:profile"])
}

@Test func inMemory_saveLoadDelete() throws {
    let store = InMemoryTokenStore()
    let id = UUID()
    #expect(try store.load(id) == nil)
    try store.save(sample(), for: id)
    #expect(try store.load(id) == sample())
    try store.delete(id)
    #expect(try store.load(id) == nil)
}

// Runs only when RUN_KEYCHAIN_TESTS=1 (writes to the login keychain).
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_KEYCHAIN_TESTS"] == "1"))
func keychain_roundtrip() throws {
    let store = KeychainTokenStore(service: "cz.mihalic.claude-status-bar.tests")
    let id = UUID()
    defer { try? store.delete(id) }
    try store.save(sample(), for: id)
    #expect(try store.load(id) == sample())
    try store.delete(id)
    #expect(try store.load(id) == nil)
}

private final class StubKeychainWrites: KeychainWriting, @unchecked Sendable {
    var statuses: [OSStatus]
    var operations: [String] = []
    var writtenData: Data?
    init(_ statuses: [OSStatus]) { self.statuses = statuses }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        operations.append("update")
        let status = statuses.removeFirst()
        if status == errSecSuccess { writtenData = attributes[kSecValueData as String] as? Data }
        return status
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        operations.append("add")
        return statuses.removeFirst()
    }
}

@Test func keychain_failedUpdateDoesNotDeleteOrReplaceCredentials() throws {
    let writes = StubKeychainWrites([errSecInteractionNotAllowed])
    writes.writtenData = Data("existing-grant".utf8)
    let store = KeychainTokenStore(service: "test", writes: writes)
    #expect(throws: KeychainError.status(errSecInteractionNotAllowed)) {
        try store.save(sample(), for: UUID())
    }
    #expect(writes.operations == ["update"])
    #expect(writes.writtenData == Data("existing-grant".utf8))
}

@Test func keychain_duplicateCreationRetriesUpdate() throws {
    let writes = StubKeychainWrites([errSecItemNotFound, errSecDuplicateItem, errSecSuccess])
    try KeychainTokenStore(service: "test", writes: writes).save(sample(), for: UUID())
    #expect(writes.operations == ["update", "add", "update"])
    #expect(try JSONDecoder().decode(TokenBundle.self, from: #require(writes.writtenData)) == sample())
}
