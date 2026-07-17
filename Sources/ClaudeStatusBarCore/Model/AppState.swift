// Sources/ClaudeStatusBarCore/Model/AppState.swift
import Foundation
import Observation

@Observable public final class AppState {
    public var accounts: [Account] = []
    public var lastError: String?
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

    /// Highest utilization across every window of every account (0...100).
    public var maxUtilization: Double? {
        let all = accounts.compactMap(\.lastSnapshot).flatMap { snap -> [Double] in
            [snap.session.utilization, snap.weekAll.utilization]
                + snap.weekPremium.map(\.utilization)
        }
        return all.max()
    }
}
