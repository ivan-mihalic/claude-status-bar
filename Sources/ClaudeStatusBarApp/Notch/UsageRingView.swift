// Sources/ClaudeStatusBarApp/Notch/UsageRingView.swift
import SwiftUI

/// One account: a progress ring around a glyph, with its percentage underneath.
public struct UsageRingView: View {
    let model: RingModel
    let diameter: CGFloat

    public init(model: RingModel, diameter: CGFloat = 46) {
        self.model = model; self.diameter = diameter
    }

    private var tint: Color {
        switch model.level {
        case .ok:       return .green
        case .warn:     return .yellow
        case .critical: return .red
        case .unknown:  return .secondary
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

    public var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max((model.percent ?? 0) / 100, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // A badge *replaces* the glyph rather than sitting beside it: the number
                // behind it may be stale and must not look authoritative.
                Image(systemName: badgeSymbol ?? "gauge.medium")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(badgeSymbol == nil ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            }
            .frame(width: diameter, height: diameter)
            Text(model.percent.map(Format.percent) ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .help(model.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.label))
        .accessibilityValue(Text((model.percent.map(Format.percent) ?? "no data") + accessibilityStatus))
    }
}
