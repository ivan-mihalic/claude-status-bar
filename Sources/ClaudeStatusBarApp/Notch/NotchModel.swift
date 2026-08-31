// Sources/ClaudeStatusBarApp/Notch/NotchModel.swift
import Foundation
import ClaudeStatusBarCore

/// Why a ring cannot be taken at face value. `nil` means the numbers are current.
public enum RingBadge: Equatable, Sendable { case offline, signIn, rateLimited, syncing }

public struct RingModel: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Account name, for the popover title and the tooltip.
    public let label: String
    /// Short per-account prefix, drawn in the middle of the ring when set.
    public let prefix: String?
    /// Outer ring: the worst weekly window (All models / Opus, whichever is higher).
    public let weekPercent: Double?
    /// Inner ring: the current 5-hour session.
    public let sessionPercent: Double?
    /// Worst of everything — what the menu-bar icon colours itself by.
    public let level: IndicatorLevel
    public let badge: RingBadge?
    /// Every window, in display order, for the popover's progress bars.
    public let windows: [UsageWindow]

    public init(id: UUID, label: String, prefix: String?, weekPercent: Double?,
                sessionPercent: Double?, level: IndicatorLevel, badge: RingBadge?,
                windows: [UsageWindow]) {
        self.id = id; self.label = label; self.prefix = prefix
        self.weekPercent = weekPercent; self.sessionPercent = sessionPercent
        self.level = level; self.badge = badge; self.windows = windows
    }
}

public enum NotchModel {
    public static func rings(accounts: [Account]) -> [RingModel] { accounts.map(ring(for:)) }

    public static func ring(for account: Account) -> RingModel {
        let snap = account.lastSnapshot
        // Outer and inner must be *different* numbers or the second ring says nothing:
        // outer is the weekly picture, inner is the session.
        let week = snap.map { s in
            ([s.weekAll.utilization] + s.weekPremium.map(\.utilization)).max() ?? 0
        }
        let session = snap?.session.utilization
        let worst = snap.map { $0.allWindows.map(\.utilization).max() ?? 0 }
        let prefix = account.menuBarPrefix?.trimmingCharacters(in: .whitespaces)

        return RingModel(id: account.id,
                         label: account.label,
                         prefix: (prefix?.isEmpty ?? true) ? nil : prefix,
                         weekPercent: week,
                         sessionPercent: session,
                         level: MenuBarIndicator.level(maxUtilization: worst),
                         badge: badge(for: account.status),
                         windows: snap?.allWindows ?? [])
    }

    /// Exhaustive on purpose: a status added later breaks the build here rather than
    /// silently rendering as "fine".
    private static func badge(for status: AccountStatus) -> RingBadge? {
        switch status {
        case .ok:           return nil
        case .offline:      return .offline
        case .needsReauth:  return .signIn
        case .rateLimited:  return .rateLimited
        case .never:        return .syncing
        }
    }
}
