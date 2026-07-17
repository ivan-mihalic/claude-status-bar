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
            ProgressView(value: min(window.utilization, 100), total: 100).tint(tint)
            Text(resetText)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
