// Sources/ClaudeStatusBarCore/Sync/SyncScheduler.swift
import Foundation

public enum SyncScheduler {
    public static func staggerOffset(index: Int,
                                     spacing: TimeInterval) -> TimeInterval {
        TimeInterval(index) * spacing
    }

    /// Longest an account may sit idle while rate-limited. A weekly limit can reset
    /// days out, and sleeping that whole time would strand the account if the reset
    /// time were ever wrong or the block lifted early — so re-check at least hourly.
    public static let maxRateLimitedInterval: TimeInterval = 3600

    public static func nextInterval(base: Int, status: AccountStatus,
                                    consecutiveRateLimits: Int,
                                    now: Date,
                                    backoff: Backoff = .usage) -> TimeInterval {
        switch status {
        case .rateLimited(let retryAt):
            let untilRetry = max(0, retryAt.timeIntervalSince(now))
            let backoffDelay = backoff.delay(forFailureCount: consecutiveRateLimits)
            return min(max(untilRetry, backoffDelay), maxRateLimitedInterval)
        default:
            return TimeInterval(base)
        }
    }
}
