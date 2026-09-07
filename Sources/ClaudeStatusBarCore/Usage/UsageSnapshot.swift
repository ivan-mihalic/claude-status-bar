// Sources/ClaudeStatusBarCore/Usage/UsageSnapshot.swift
import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let utilization: Double   // 0...100
    public let resetsAt: Date
    public init(key: String, label: String, utilization: Double, resetsAt: Date) {
        self.key = key; self.label = label
        self.utilization = utilization; self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    /// Providers can expose either, both, or neither named window. Claude always supplies
    /// both; Codex legitimately returns only a weekly window for some subscriptions.
    public let session: UsageWindow?
    public let weekAll: UsageWindow?
    public let weekPremium: [UsageWindow]
    public let fetchedAt: Date
    public init(session: UsageWindow?, weekAll: UsageWindow?,
                weekPremium: [UsageWindow], fetchedAt: Date) {
        self.session = session; self.weekAll = weekAll
        self.weekPremium = weekPremium; self.fetchedAt = fetchedAt
    }

    public var allWindows: [UsageWindow] { [session, weekAll].compactMap { $0 } + weekPremium }

    /// Worst window, without building the array. `allWindows` allocates on every call, and
    /// this question gets asked on paths that run per pointer move and per sync.
    public var maxUtilization: Double {
        var worst = max(session?.utilization ?? 0, weekAll?.utilization ?? 0)
        for window in weekPremium { worst = max(worst, window.utilization) }
        return worst
    }

    /// When the soonest maxed-out window frees up again, if any is maxed out and its
    /// reset still lies ahead. Lets a rate-limited account wait for the actual reset
    /// instead of hammering a backoff that just re-hits the same limit.
    public func nextResetForExhaustedWindow(now: Date,
                                            threshold: Double = 100) -> Date? {
        allWindows
            .filter { $0.utilization >= threshold && $0.resetsAt > now }
            .map(\.resetsAt)
            .min()
    }
}
