// Sources/ClaudeStatusBarCore/Model/Account.swift
import Foundation

public enum AccountStatus: Equatable, Codable, Sendable {
    case ok
    case rateLimited(retryAt: Date)
    case needsReauth
    case offline
    case never
}

public struct Account: Identifiable, Codable, Equatable, Sendable {
    public static let intervalFloor = 60
    public static let intervalDefault = 300

    public let id: UUID
    public var label: String
    public var accountUuid: String?
    public var syncInterval: Int
    public var status: AccountStatus
    public var lastSnapshot: UsageSnapshot?
    public var lastSyncedAt: Date?

    public init(id: UUID, label: String, accountUuid: String?,
                syncInterval: Int, status: AccountStatus,
                lastSnapshot: UsageSnapshot?, lastSyncedAt: Date?) {
        self.id = id; self.label = label; self.accountUuid = accountUuid
        self.syncInterval = syncInterval; self.status = status
        self.lastSnapshot = lastSnapshot; self.lastSyncedAt = lastSyncedAt
    }

    public var effectiveInterval: Int { max(syncInterval, Self.intervalFloor) }
}
