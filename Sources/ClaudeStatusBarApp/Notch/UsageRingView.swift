// Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift
import SwiftUI

/// One account, as two concentric arcs: the outer is the worst weekly window, the inner is
/// the current session. No number is drawn here — the figures live in the popover, next to
/// the bar they belong to, where they can be labelled.
public struct UsageRingView: View {
    let model: RingModel
    let diameter: CGFloat

    public init(model: RingModel, diameter: CGFloat = NotchMetrics.ringDiameter) {
        self.model = model; self.diameter = diameter
    }

    private static func tint(_ percent: Double?) -> Color {
        switch MenuBarIndicator.level(maxUtilization: percent) {
        case .ok:       return .green
        case .warn:     return .yellow
        case .critical: return .red
        case .unknown:  return Color.white.opacity(0.35)
        }
    }

    private var badgeSymbol: String? {
        switch model.badge {
        case .none:        return nil
        case .offline:     return "wifi.slash"
        case .signIn:      return "person.badge.key"
        case .rateLimited: return "clock.badge.exclamationmark"
        case .syncing:     return "arrow.triangle.2.circlepath"
        }
    }

    private var accessibilityStatus: String {
        switch model.badge {
        case .none:        return ""
        case .offline:     return ", offline"
        case .signIn:      return ", needs sign-in"
        case .rateLimited: return ", rate limited"
        case .syncing:     return ", syncing"
        }
    }

    @ViewBuilder private func arc(percent: Double?, inset: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max((percent ?? 0) / 100, 0), 1))
                .stroke(Self.tint(percent), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    /// The centre: the account's own prefix if it has one, otherwise a glyph. A failure badge
    /// wins over both — the arcs behind it may be stale and must not look authoritative.
    @ViewBuilder private var centre: some View {
        if let badgeSymbol {
            Image(systemName: badgeSymbol)
                .font(.system(size: diameter * 0.26, weight: .semibold))
                .foregroundStyle(Self.tint(model.weekPercent))
        } else if let prefix = model.prefix {
            Text(prefix)
                .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: diameter * 0.48)
        } else {
            Image(systemName: "gauge.medium")
                .font(.system(size: diameter * 0.28, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    public var body: some View {
        ZStack {
            arc(percent: model.weekPercent, inset: 0, width: 4)
            arc(percent: model.sessionPercent, inset: 8, width: 3)
            centre
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .help(model.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.label))
        .accessibilityValue(Text(
            "week " + (model.weekPercent.map(Format.percent) ?? "no data")
            + ", session " + (model.sessionPercent.map(Format.percent) ?? "no data")
            + accessibilityStatus))
    }
}
