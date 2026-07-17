// Sources/ClaudeStatusBarApp/Views/AccountRowView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct AccountRowView: View {
    let account: Account
    let now: Date
    public init(account: Account, now: Date) { self.account = account; self.now = now }

    @ViewBuilder private var statusBadge: some View {
        switch account.status {
        case .ok:            EmptyView()
        case .rateLimited(let retryAt):
            Label("retry \(Format.resetCountdown(to: retryAt, now: now).replacingOccurrences(of: "resets ", with: ""))",
                  systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
        case .needsReauth:   Label("sign in", systemImage: "person.badge.key").foregroundStyle(.red)
        case .offline:       Label("offline", systemImage: "wifi.slash").foregroundStyle(.secondary)
        case .never:         Label("syncing…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(account.label).font(.headline); Spacer(); statusBadge.font(.caption) }
            if let snap = account.lastSnapshot {
                UsageBarView(window: snap.session, now: now)
                UsageBarView(window: snap.weekAll, now: now)
                if let premium = snap.weekPremium.first { UsageBarView(window: premium, now: now) }
            } else {
                Text("No data yet").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
