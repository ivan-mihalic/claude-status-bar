// Sources/ClaudeStatusBarApp/Sync/SyncReducer.swift
import Foundation
import ClaudeStatusBarCore

public struct SyncState: Equatable, Sendable {
    public var account: Account
    public var consecutiveRateLimits: Int
    public init(account: Account, consecutiveRateLimits: Int) {
        self.account = account; self.consecutiveRateLimits = consecutiveRateLimits
    }
}

public enum SyncReducer {
    public static func reduce(_ state: SyncState, outcome: SyncOutcome,
                              now: Date, backoff: Backoff = .usage) -> SyncState {
        var s = state
        switch outcome {
        case .success(let snap):
            s.account.status = .ok
            s.account.lastSnapshot = snap
            s.account.lastSyncedAt = now
            s.consecutiveRateLimits = 0
        case .rateLimited:
            s.consecutiveRateLimits += 1
            let delay = backoff.delay(forFailureCount: s.consecutiveRateLimits)
            s.account.status = .rateLimited(retryAt: now.addingTimeInterval(delay))
        case .needsReauth:
            s.account.status = .needsReauth
            s.consecutiveRateLimits = 0
        case .offline, .failed:
            s.account.status = .offline
            s.consecutiveRateLimits = 0
        }
        return s
    }
}
