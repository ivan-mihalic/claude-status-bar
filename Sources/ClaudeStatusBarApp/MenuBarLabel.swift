import Foundation
import ClaudeStatusBarCore

/// Computes the text shown next to the menu-bar gauge icon.
public enum MenuBarLabel {
    /// - showAccountPercents ON  → for every account the user kept in the menu bar:
    ///   "<prefix> S/W[/P]" (session/week/premium percentages, rounded), joined by two spaces.
    /// - otherwise → **nothing**. The gauge icon already carries the warning by its shape and
    ///   colour, so a bare number beside it only widened an already crowded menu bar without
    ///   saying whose number it was.
    ///
    /// Hiding an account only shortens the label; it never mutes it. The icon's level is
    /// computed from *every* account (`AppState.maxUtilization`), hidden ones included.
    public static func text(accounts: [Account], showAccountPercents: Bool) -> String {
        guard showAccountPercents else { return "" }
        let listed = accounts.filter(\.isShownInMenuBar)
        guard !listed.isEmpty else { return "" }
        return listed.map(perAccount).joined(separator: "  ")
    }

    private static func perAccount(_ a: Account) -> String {
        let prefix = (a.menuBarPrefix ?? "").trimmingCharacters(in: .whitespaces)
        guard let s = a.lastSnapshot else {
            return prefix.isEmpty ? "…" : "\(prefix) …"
        }
        let visible = [s.session, s.weekAll].compactMap { $0 } + s.weekPremium.prefix(1)
        let nums = visible.map { pct($0.utilization) }
        let numStr = nums.joined(separator: "/")
        return prefix.isEmpty ? numStr : "\(prefix) \(numStr)"
    }

    private static func pct(_ u: Double) -> String { "\(Int(u.rounded()))" }
}
