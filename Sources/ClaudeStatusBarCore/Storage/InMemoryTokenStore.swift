// Sources/ClaudeStatusBarCore/Storage/InMemoryTokenStore.swift
import Foundation

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var storage: [UUID: TokenBundle] = [:]
    private let lock = NSLock()
    public init() {}
    public func save(_ bundle: TokenBundle, for id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; storage[id] = bundle
    }
    public func load(_ id: UUID) throws -> TokenBundle? {
        lock.lock(); defer { lock.unlock() }; return storage[id]
    }
    public func delete(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; storage[id] = nil
    }
}
