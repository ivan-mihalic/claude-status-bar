// Tests/ClaudeStatusBarCoreTests/TokenStoreTests.swift
import Testing
import Foundation
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
