// Sources/ClaudeStatusBarCore/Model/AppState.swift
import Foundation
import Observation

@Observable public final class AppState {
    public var accounts: [Account] = []
    public private(set) var lastError: String?
    public init() {}

    /// Surfaces a failure to the user. The message is redacted before storage
    /// so secrets never end up on screen.
    public func report(_ message: String) { lastError = Redaction.redact(message) }

    public func clearError() { lastError = nil }

    public func upsert(_ account: Account) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
    }

    public func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
    }

    /// Shifts an account by `offset` positions (-1 = up, +1 = down). The array order
    /// is the display order everywhere (dashboard tiles, popover rows, menu-bar label)
    /// and is what `SnapshotStore` persists, so a move is all that "reordering" needs.
    /// Returns false — and changes nothing — when the account is unknown or the move
    /// would run off either end.
    @discardableResult
    public func move(_ id: UUID, by offset: Int) -> Bool {
        guard let from = accounts.firstIndex(where: { $0.id == id }) else { return false }
        let to = from + offset
        guard to >= 0, to < accounts.count, to != from else { return false }
        let account = accounts.remove(at: from)
        accounts.insert(account, at: to)
        return true
    }

    /// Highest utilization across every window of every account (0...100).
    public var maxUtilization: Double? {
        let all = accounts.compactMap(\.lastSnapshot).flatMap { snap -> [Double] in
            [snap.session.utilization, snap.weekAll.utilization]
                + snap.weekPremium.map(\.utilization)
        }
        return all.max()
    }
}
