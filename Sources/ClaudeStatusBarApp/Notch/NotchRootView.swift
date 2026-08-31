// Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift
import SwiftUI

/// The panel's content. Sits inside a fixed-size window and draws the collapsed pill or the
/// expanded stack of rings; the window itself never changes.
///
/// `onOpenDashboard` is injected rather than read from `@Environment(\.openWindow)` because
/// this view is hosted in a detached `NSPanel`, outside the SwiftUI scene graph, where the
/// scene environment is not guaranteed to reach it.
public struct NotchRootView: View {
    @Bindable var env: AppEnvironment
    let layout: NotchLayout
    let expanded: Bool
    let onOpenDashboard: () -> Void

    public init(env: AppEnvironment, layout: NotchLayout, expanded: Bool,
                onOpenDashboard: @escaping () -> Void) {
        self.env = env; self.layout = layout
        self.expanded = expanded; self.onOpenDashboard = onOpenDashboard
    }

    public var body: some View {
        let rings = Array(NotchModel.rings(accounts: env.appState.accounts)
            .prefix(NotchMetrics.maxRings))
        let width = expanded ? NotchMetrics.expandedWidth : layout.collapsed.width
        let height = expanded
            ? NotchMetrics.expandedHeight(collapsedHeight: layout.collapsed.height,
                                          ringCount: rings.count)
            : layout.collapsed.height

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape().fill(.black)
                if expanded {
                    VStack(spacing: 14) {
                        if rings.isEmpty {
                            Text("No accounts")
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        } else {
                            ForEach(rings) { UsageRingView(model: $0) }
                        }
                        Button(action: onOpenDashboard) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: NotchMetrics.gearSlot, height: NotchMetrics.gearSlot)
                                .background(Circle().fill(.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help("Open Dashboard")
                    }
                    .padding(.top, layout.collapsed.height + NotchMetrics.topGap)
                    .padding(.bottom, NotchMetrics.bottomPadding)
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: expanded)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
