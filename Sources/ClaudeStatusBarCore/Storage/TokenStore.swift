// Sources/ClaudeStatusBarCore/Storage/TokenStore.swift
import Foundation

public protocol TokenStore: Sendable {
    func save(_ bundle: TokenBundle, for id: UUID) throws
    func load(_ id: UUID) throws -> TokenBundle?
    func delete(_ id: UUID) throws
}
