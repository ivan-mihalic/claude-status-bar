// Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift
import SwiftUI
import ClaudeStatusBarCore

/// One account, as two concentric arcs: the outer is the worst weekly window, the inner is
/// the current session. No number is drawn here — the figures live in the popover, next to
/// the bar they belong to, where they can be labelled.
public struct UsageRingView: View {
    let model: RingModel
    let diameter: CGFloat

    public init(model: RingModel, diameter: CGFloat = NotchMetrics.ringDiameter) {
        self.model = model; self.diameter = diameter
    }

    private func tint(_ percent: Double?) -> Color {
        if let selected = model.ringColor, percent != nil {
            return Color(red: selected.red, green: selected.green, blue: selected.blue,
                         opacity: selected.opacity)
        }
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
                .stroke(tint(percent), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    /// The centre: the account's own prefix if it has one, otherwise a glyph. A failure badge
    /// wins over both — the arcs behind it may be stale and must not look authoritative.
    ///
    /// Every size here goes through `animatableFont` rather than `.font(.system(size:))`. The
    /// arcs around this glyph grow by interpolation — frames, `trim`, `StrokeStyle` all carry
    /// animatable data — but a `Font` does not, so a plain `.font` made the letter jump to its
    /// new size while the ring was still growing around it.
    @ViewBuilder private var centre: some View {
        if let badgeSymbol {
            Image(systemName: badgeSymbol)
                .animatableFont(size: diameter * 0.26, weight: .semibold)
                .foregroundStyle(tint(model.weekPercent))
        } else if let prefix = model.prefix {
            Text(prefix)
                .animatableFont(size: diameter * 0.30, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: diameter * 0.48)
        } else {
            ProviderMarkView(provider: model.provider, diameter: diameter * 0.40)
        }
    }

    public var body: some View {
        ZStack {
            arc(percent: model.weekPercent, inset: 0, width: max(diameter * 0.085, 2.5))
            arc(percent: model.sessionPercent, inset: max(diameter * 0.17, 5),
                width: max(diameter * 0.065, 2))
            centre
        }
        .frame(width: diameter, height: diameter)
        // The provider mark sits off the ring's top-right shoulder rather than on it: pushed
        // far enough out that it clears the outer arc, which is the arc carrying the weekly
        // number and the one worth reading at a glance.
        .overlay(alignment: .topTrailing) {
            if model.prefix != nil {
                ProviderMarkView(provider: model.provider, diameter: max(diameter * 0.32, 11))
                    .offset(x: diameter * 0.22, y: -diameter * 0.22)
            }
        }
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
