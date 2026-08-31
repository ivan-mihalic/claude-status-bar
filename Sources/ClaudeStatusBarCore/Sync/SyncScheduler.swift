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

    /// Longest an ordinary account may sit between syncs once the adaptive and energy
    /// factors have been applied. An account that goes quiet must not go dark.
    public static let maxAdaptiveInterval: TimeInterval = 3600

    /// How much to stretch the interval for an account at this utilization.
    ///
    /// The whole point of polling is to catch a limit before it bites. At 5 % that question
    /// has the same answer for the next half hour; at 90 % it changes minute to minute. So
    /// the interval follows the number, and the user's own setting stays the *floor*.
    public static func adaptiveMultiplier(utilization: Double?) -> Double {
        // No snapshot yet means no answer yet — slowing those first syncs down would leave
        // a freshly added account blank for half an hour.
        guard let utilization else { return 1 }
        if utilization >= 80 { return 1 }
        if utilization >= 20 { return 3 }
        return 6
    }

    /// - Parameter utilization: worst window of this account, or `nil` when it has never
    ///   synced. Drives `adaptiveMultiplier`.
    /// - Parameter energyMultiplier: from `EnergyPolicy.syncMultiplier` — battery and Low
    ///   Power Mode. Multiplies on top of the adaptive factor.
    public static func nextInterval(base: Int, status: AccountStatus,
                                    consecutiveRateLimits: Int,
                                    now: Date,
                                    backoff: Backoff = .usage,
                                    utilization: Double? = nil,
                                    energyMultiplier: Double = 1) -> TimeInterval {
        switch status {
        case .rateLimited(let retryAt):
            // Rate limiting has its own arithmetic, tied to when the limit actually lifts.
            // Stretching it to save power would keep the account waiting long after it
            // could have worked again.
            let untilRetry = max(0, retryAt.timeIntervalSince(now))
            let backoffDelay = backoff.delay(forFailureCount: consecutiveRateLimits)
            return min(max(untilRetry, backoffDelay), maxRateLimitedInterval)
        default:
            let interval = TimeInterval(base)
                * adaptiveMultiplier(utilization: utilization)
                * max(energyMultiplier, 1)
            // The cap never shortens a user who deliberately asked for a long interval.
            return min(interval, max(TimeInterval(base), maxAdaptiveInterval))
        }
    }
}
