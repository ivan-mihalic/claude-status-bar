// Sources/ClaudeStatusBarApp/Views/AccountRowView.swift
import SwiftUI
import ClaudeStatusBarCore

/// Move-up / move-down affordance for a tile. Passed in by the dashboard (which knows
/// each tile's index); `nil` in the menu-bar popover, where reordering isn't offered.
public struct ReorderControls {
    public let canMoveUp: Bool
    public let canMoveDown: Bool
    /// -1 = one slot up, +1 = one slot down.
    public let move: (Int) -> Void

    public init(canMoveUp: Bool, canMoveDown: Bool, move: @escaping (Int) -> Void) {
        self.canMoveUp = canMoveUp; self.canMoveDown = canMoveDown; self.move = move
    }
}

public struct AccountRowView: View {
    let account: Account
    let now: Date
    /// Trigger a manual sync for this account. When nil, the sync button is hidden.
    let onManualSync: (() async -> Void)?
    /// Reorder chevrons in the header. When nil, they're hidden.
    let reorder: ReorderControls?
    @State private var syncing = false

    public init(account: Account, now: Date, onManualSync: (() async -> Void)? = nil,
                reorder: ReorderControls? = nil) {
        self.account = account; self.now = now; self.onManualSync = onManualSync
        self.reorder = reorder
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

    /// Deliberately quiet: small tertiary chevrons with no button chrome, so the
    /// header stays about the account, not about its controls.
    @ViewBuilder private func reorderButtons(_ r: ReorderControls) -> some View {
        HStack(spacing: 1) {
            Button { r.move(-1) } label: { chevron("chevron.up") }
                .disabled(!r.canMoveUp).help("Move this account up")
            Button { r.move(1) } label: { chevron("chevron.down") }
                .disabled(!r.canMoveDown).help("Move this account down")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .semibold))
            .frame(width: 16, height: 12)
            .contentShape(Rectangle())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(account.label).font(.headline)
                Spacer()
                statusBadge.font(.caption)
                if let reorder { reorderButtons(reorder) }
            }
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
                if account.lastAttemptFailed {
                    // A failed sync leaves `lastSyncedAt` alone on purpose, so without this
                    // the button looks like it did nothing at all.
                    Text("tried \(Format.lastSync(account.lastAttemptAt, now: now)) — no luck")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }.padding(.vertical, 4)
    }
}
