// Sources/ClaudeStatusBarApp/Views/UsageBarView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct UsageBarView: View {
    let window: UsageWindow
    let now: Date
    public init(window: UsageWindow, now: Date) { self.window = window; self.now = now }

    private var tint: Color {
        switch MenuBarIndicator.level(maxUtilization: window.utilization) {
        case .critical: return .red
        case .warn: return .orange
        default: return .green
        }
    }

    private var resetText: String {
        let base = Format.resetCountdown(to: window.resetsAt, now: now)
        // Weekly windows also show the absolute reset day/date/time in parentheses.
        if window.key.hasPrefix("seven_day") {
            return "\(base) (\(Format.absoluteReset(window.resetsAt)))"
        }
        return base
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.percent(window.utilization)).font(.caption.monospacedDigit())
            }
            // A hand-rolled bar rather than ProgressView: on macOS, ProgressView's
            // .tint() does not reliably re-color the underlying NSProgressIndicator
            // when the value/tint changes after first render, so a bar first drawn red
            // (utilization ≥ 90) could stay red after the value later dropped. A Capsule
            // whose fill is bound directly to `tint` always matches the current value.
            UsageBar(fraction: min(window.utilization, 100) / 100, color: tint)
            Text(resetText)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Determinate usage bar whose fill color is a pure function of the current value.
struct UsageBar: View {
    let fraction: Double   // 0...1
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}
