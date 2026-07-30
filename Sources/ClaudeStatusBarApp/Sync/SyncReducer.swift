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
        case .rateLimited(let retryAfter):
            s.consecutiveRateLimits += 1
            // Best information first: what the server asked for, then the reset time of
            // whichever window is actually maxed out (the app already knows it from the
            // last snapshot), and only then a blind backoff.
            let retryAt: Date
            if let retryAfter {
                retryAt = now.addingTimeInterval(retryAfter)
            } else if let reset = s.account.lastSnapshot?.nextResetForExhaustedWindow(now: now) {
                retryAt = reset
            } else {
                retryAt = now.addingTimeInterval(
                    backoff.delay(forFailureCount: s.consecutiveRateLimits))
            }
            s.account.status = .rateLimited(retryAt: retryAt)
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
