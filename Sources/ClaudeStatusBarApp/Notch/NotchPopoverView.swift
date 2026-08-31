// Sources/ClaudeStatusBarApp/Notch/NotchPopoverView.swift
import SwiftUI
import ClaudeStatusBarCore

/// The detail card that opens beside a hovered ring: the same windows the Dashboard tile
/// shows, as labelled bars — this is the only place a percentage is written out.
///
/// It repeats `UsageBarView`'s layout rather than reusing it because that view is styled for
/// the app's light window chrome (`.secondary`, `.quaternary`) and would be unreadable on
/// the panel's black.
public struct NotchPopoverView: View {
    let model: RingModel
    let now: Date
    /// Fetches this account's numbers right now. Ad-hoc on purpose: it does not wait for the
    /// poll interval and does not reschedule it — the timer loop sleeps on its own clock, so
    /// pressing this neither delays nor advances the next automatic sync.
    let onRefreshNow: () async -> Void
    @State private var refreshing = false

    public init(model: RingModel, now: Date, onRefreshNow: @escaping () async -> Void = {}) {
        self.model = model; self.now = now; self.onRefreshNow = onRefreshNow
    }

    private func tint(_ u: Double) -> Color {
        switch MenuBarIndicator.level(maxUtilization: u) {
        case .critical: return .red
        case .warn:     return .yellow
        default:        return .green
        }
    }

    private func resetText(_ w: UsageWindow) -> String {
        let base = Format.resetCountdown(to: w.resetsAt, now: now)
        return w.key.hasPrefix("seven_day")
            ? "\(base) (\(Format.absoluteReset(w.resetsAt)))"
            : base
    }

    private var statusNote: String? {
        switch model.badge {
        case .none:        return nil
        case .offline:     return "Offline — these numbers may be out of date"
        case .signIn:      return "Sign in again to refresh"
        case .rateLimited: return "Rate limited — retrying later"
        case .syncing:     return "Syncing…"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let prefix = model.prefix {
                    Text(prefix)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
                Text(model.label).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                // Named, not just marked: the glyph on the ring is small and abstract, and a
                // panel mixing services should say in words whose limits these are.
                Text(model.provider.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .fixedSize()
            }
            .foregroundStyle(.white)

            if let statusNote {
                Text(statusNote).font(.caption2).foregroundStyle(.orange)
            }

            HStack(spacing: 6) {
                Text("Last sync").font(.caption2).foregroundStyle(.white.opacity(0.55))
                Text(Format.lastSync(model.lastSyncedAt, now: now))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                Button {
                    guard !refreshing else { return }
                    refreshing = true
                    Task { await onRefreshNow(); refreshing = false }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.white.opacity(0.14)))
                        .rotationEffect(.degrees(refreshing ? 360 : 0))
                        .animation(refreshing
                                   ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                   : .default, value: refreshing)
                }
                .buttonStyle(.plain)
                .disabled(refreshing)
                .help("Sync this account now. Does not change when the next automatic sync happens.")
                Spacer()
            }

            if model.windows.isEmpty {
                Text("No data yet").font(.caption).foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(model.windows, id: \.key) { w in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(w.label).font(.caption).foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            Text(Format.percent(w.utilization))
                                .font(.caption.monospacedDigit()).foregroundStyle(.white)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15))
                                Capsule().fill(tint(w.utilization))
                                    .frame(width: min(max(w.utilization, 0), 100) / 100 * geo.size.width)
                            }
                        }
                        .frame(height: 6)
                        Text(resetText(w)).font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: NotchMetrics.popoverWidth, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black))
    }
}
