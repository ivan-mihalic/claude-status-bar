// Sources/ClaudeStatusBarCore/Sync/SyncScheduler.swift
import Foundation

public enum SyncScheduler {
    public static func staggerOffset(index: Int,
                                     spacing: TimeInterval) -> TimeInterval {
        TimeInterval(index) * spacing
    }

    public static func nextInterval(base: Int, status: AccountStatus,
                                    consecutiveRateLimits: Int,
                                    now: Date,
                                    backoff: Backoff = .usage) -> TimeInterval {
        switch status {
        case .rateLimited(let retryAt):
            let untilRetry = max(0, retryAt.timeIntervalSince(now))
            let backoffDelay = backoff.delay(forFailureCount: consecutiveRateLimits)
            return max(untilRetry, backoffDelay)
        default:
            return TimeInterval(base)
        }
    }
}
