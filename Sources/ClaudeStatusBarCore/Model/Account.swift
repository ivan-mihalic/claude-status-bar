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
    /// Optional short label shown before this account's percentages in the menu bar.
    /// Optional so old persisted snapshots (without this key) still decode.
    public var menuBarPrefix: String?
    /// Whether this account gets a ring in the notch panel. Optional for the same reason:
    /// accounts saved before the panel existed decode as `nil`, and `nil` means shown —
    /// turning a feature on must not silently hide someone's account.
    public var showInNotch: Bool?
    /// Whether this account's percentages appear in the menu-bar label. Optional for decode
    /// compatibility; `nil` means shown. Hiding is about menu-bar width — a hidden account
    /// still syncs and still drives the warning icon.
    public var showInMenuBar: Bool?
    /// Which service the account belongs to. Optional for decode compatibility; `nil` is
    /// Claude, the only provider the app can talk to today.
    public var provider: Provider?

    public init(id: UUID, label: String, accountUuid: String?,
                syncInterval: Int, status: AccountStatus,
                lastSnapshot: UsageSnapshot?, lastSyncedAt: Date?,
                menuBarPrefix: String? = nil, showInNotch: Bool? = nil,
                showInMenuBar: Bool? = nil, provider: Provider? = nil) {
        self.id = id; self.label = label; self.accountUuid = accountUuid
        self.syncInterval = syncInterval; self.status = status
        self.lastSnapshot = lastSnapshot; self.lastSyncedAt = lastSyncedAt
        self.menuBarPrefix = menuBarPrefix
        self.showInNotch = showInNotch
        self.showInMenuBar = showInMenuBar
        self.provider = provider
    }

    public var effectiveInterval: Int { max(syncInterval, Self.intervalFloor) }

    /// Shown in the notch unless explicitly hidden.
    public var isShownInNotch: Bool { showInNotch ?? true }

    /// Listed in the menu-bar label unless explicitly hidden.
    public var isShownInMenuBar: Bool { showInMenuBar ?? true }

    public var effectiveProvider: Provider { provider ?? .claude }
}
