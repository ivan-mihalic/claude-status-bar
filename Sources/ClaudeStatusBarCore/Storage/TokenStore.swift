// Sources/ClaudeStatusBarCore/Storage/TokenStore.swift
import Foundation

public protocol TokenStore: Sendable {
    func save(_ bundle: TokenBundle, for id: UUID) throws
    func load(_ id: UUID) throws -> TokenBundle?
    func delete(_ id: UUID) throws
    func replace(_ bundle: TokenBundle, for id: UUID, matching previous: TokenBundle?) throws -> Bool
}

extension TokenStore {
    /// Pro testovací nebo výhradně sériová úložiště. Produkční úložiště musí
    /// přepsání implementovat atomicky vůči ostatním zápisům stejné instance.
    public func replace(_ bundle: TokenBundle, for id: UUID, matching previous: TokenBundle?) throws -> Bool {
        guard try load(id) == previous else { return false }
        try save(bundle, for: id)
        return true
    }
}
