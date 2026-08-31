// Sources/ClaudeStatusBarApp/Notch/NotchModel.swift
import Foundation
import ClaudeStatusBarCore

/// Why a ring cannot be taken at face value. `nil` means the number is current.
public enum RingBadge: Equatable, Sendable { case offline, signIn, rateLimited, syncing }

public struct RingModel: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    /// Worst window utilization, 0...100. `nil` = never synced successfully.
    public let percent: Double?
    public let level: IndicatorLevel
    public let badge: RingBadge?

    public init(id: UUID, label: String, percent: Double?,
                level: IndicatorLevel, badge: RingBadge?) {
        self.id = id; self.label = label; self.percent = percent
        self.level = level; self.badge = badge
    }
}

public enum NotchModel {
    public static func rings(accounts: [Account]) -> [RingModel] { accounts.map(ring(for:)) }

    /// A ring shows the account's *worst* window — the same rule the menu-bar indicator
    /// uses, so the two surfaces can never disagree about how bad things are.
    public static func ring(for account: Account) -> RingModel {
        let worst = account.lastSnapshot.map { $0.allWindows.map(\.utilization).max() ?? 0 }
        return RingModel(id: account.id,
                         label: account.menuBarPrefix ?? account.label,
                         percent: worst,
                         level: MenuBarIndicator.level(maxUtilization: worst),
                         badge: badge(for: account.status))
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
