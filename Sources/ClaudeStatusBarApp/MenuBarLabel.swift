import Foundation
import ClaudeStatusBarCore

/// Computes the text shown next to the menu-bar gauge icon.
public enum MenuBarLabel {
    /// - showAccountPercents ON  → for every account: "<prefix> S/W[/P]" (session/week/premium
    ///   percentages, rounded), joined by two spaces.
    /// - showAccountPercents OFF → the single highest utilization across all accounts/windows
    ///   (e.g. "62%"), or "—" when there's no data.
    public static func text(accounts: [Account], showAccountPercents: Bool) -> String {
        if showAccountPercents && !accounts.isEmpty {
            return accounts.map(perAccount).joined(separator: "  ")
        }
        guard let max = overallMax(accounts) else { return "—" }
        return "\(Int(max.rounded()))%"
    }

    private static func perAccount(_ a: Account) -> String {
        let prefix = (a.menuBarPrefix ?? "").trimmingCharacters(in: .whitespaces)
        guard let s = a.lastSnapshot else {
            return prefix.isEmpty ? "…" : "\(prefix) …"
        }
        var nums = [pct(s.session.utilization), pct(s.weekAll.utilization)]
        if let p = s.weekPremium.first { nums.append(pct(p.utilization)) }
        let numStr = nums.joined(separator: "/")
        return prefix.isEmpty ? numStr : "\(prefix) \(numStr)"
    }

    private static func overallMax(_ accounts: [Account]) -> Double? {
        accounts.compactMap(\.lastSnapshot).flatMap { snap -> [Double] in
            [snap.session.utilization, snap.weekAll.utilization] + snap.weekPremium.map(\.utilization)
        }.max()
    }

    private static func pct(_ u: Double) -> String { "\(Int(u.rounded()))" }
}
