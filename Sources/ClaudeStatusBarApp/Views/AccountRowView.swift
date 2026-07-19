// Sources/ClaudeStatusBarApp/Views/AccountRowView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct AccountRowView: View {
    let account: Account
    let now: Date
    /// Trigger a manual sync for this account. When nil, the sync button is hidden.
    let onManualSync: (() async -> Void)?
    @State private var syncing = false

    public init(account: Account, now: Date, onManualSync: (() async -> Void)? = nil) {
        self.account = account; self.now = now; self.onManualSync = onManualSync
    }

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
            if let onManualSync {
                Button {
                    guard !syncing else { return }
                    syncing = true
                    Task { await onManualSync(); syncing = false }
                } label: {
                    Label(syncing ? "Syncing…" : Format.relativeSync(from: account.lastSyncedAt, now: now),
                          systemImage: syncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(syncing)
                .help("Click to sync this account now")
            }
        }.padding(.vertical, 4)
    }
}
