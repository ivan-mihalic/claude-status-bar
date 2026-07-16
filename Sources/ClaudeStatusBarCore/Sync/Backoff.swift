// Sources/ClaudeStatusBarCore/Sync/Backoff.swift
import Foundation

public struct Backoff: Sendable {
    public let steps: [TimeInterval]
    public init(steps: [TimeInterval]) { self.steps = steps }

    public static let usage = Backoff(steps: [30, 60, 120, 240, 300])

    /// n == number of consecutive failures. 0 -> no delay.
    public func delay(forFailureCount n: Int) -> TimeInterval {
        guard n > 0 else { return 0 }
        return steps[min(n, steps.count) - 1]
    }
}
