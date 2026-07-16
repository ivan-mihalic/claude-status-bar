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
    public let session: UsageWindow
    public let weekAll: UsageWindow
    public let weekPremium: [UsageWindow]
    public let fetchedAt: Date
    public init(session: UsageWindow, weekAll: UsageWindow,
                weekPremium: [UsageWindow], fetchedAt: Date) {
        self.session = session; self.weekAll = weekAll
        self.weekPremium = weekPremium; self.fetchedAt = fetchedAt
    }
}
