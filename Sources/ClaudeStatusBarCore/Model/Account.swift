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
    /// When a sync was last *attempted*, whether or not it worked. Optional for decode
    /// compatibility with account files written before this existed.
    ///
    /// Separate from `lastSyncedAt` because a failed sync must not look like a successful
    /// one — and without it a failed sync leaves no trace at all, so pressing "sync now" on
    /// an account that cannot reach the server changes nothing on screen and the button
    /// reads as broken.
    public var lastAttemptAt: Date?
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
    /// Claude, which was the only provider in older account files.
    public var provider: Provider?
    /// Optional user-selected colour for both usage arcs in the notch. `nil` retains the
    /// automatic green/yellow/red utilisation colours used by older saved accounts.
    public var ringColor: AccountRingColor?

    public init(id: UUID, label: String, accountUuid: String?,
                syncInterval: Int, status: AccountStatus,
                lastSnapshot: UsageSnapshot?, lastSyncedAt: Date?,
                menuBarPrefix: String? = nil, showInNotch: Bool? = nil,
                showInMenuBar: Bool? = nil, provider: Provider? = nil,
                lastAttemptAt: Date? = nil, ringColor: AccountRingColor? = nil) {
        self.id = id; self.label = label; self.accountUuid = accountUuid
        self.syncInterval = syncInterval; self.status = status
        self.lastSnapshot = lastSnapshot; self.lastSyncedAt = lastSyncedAt
        self.lastAttemptAt = lastAttemptAt
        self.menuBarPrefix = menuBarPrefix
        self.showInNotch = showInNotch
        self.showInMenuBar = showInMenuBar
        self.provider = provider
        self.ringColor = ringColor
    }

    public var effectiveInterval: Int { max(syncInterval, Self.intervalFloor) }

    /// Shown in the notch unless explicitly hidden.
    public var isShownInNotch: Bool { showInNotch ?? true }

    /// Listed in the menu-bar label unless explicitly hidden.
    public var isShownInMenuBar: Bool { showInMenuBar ?? true }

    public var effectiveProvider: Provider { provider ?? .claude }

    /// Whether the most recent attempt failed to bring back numbers. False for an account
    /// that has never tried — there is nothing to report yet.
    public var lastAttemptFailed: Bool {
        guard let attempt = lastAttemptAt else { return false }
        guard let synced = lastSyncedAt else { return true }
        return attempt > synced
    }
}
