// Sources/ClaudeStatusBarApp/Notch/NotchRootView.swift
import SwiftUI

/// The panel's content, laid out inside a fixed-size window using rects from
/// `NotchGeometry.frames` — the same rects the hit-test path is built from, so the drawn
/// panel and the clickable panel are one thing.
///
/// `onOpenDashboard` is injected rather than read from `@Environment(\.openWindow)` because
/// this view is hosted in a detached `NSPanel`, outside the SwiftUI scene graph, where the
/// scene environment is not guaranteed to reach it.
public struct NotchRootView: View {
    @Bindable var env: AppEnvironment
    let layout: NotchLayout
    let expanded: Bool
    /// Index of the ring whose popover is open, if any.
    let popoverIndex: Int?
    let onOpenDashboard: () -> Void

    public init(env: AppEnvironment, layout: NotchLayout, expanded: Bool,
                popoverIndex: Int?, onOpenDashboard: @escaping () -> Void) {
        self.env = env; self.layout = layout; self.expanded = expanded
        self.popoverIndex = popoverIndex
        self.onOpenDashboard = onOpenDashboard
    }

    private var rings: [RingModel] {
        Array(NotchModel.rings(accounts: env.appState.accounts).prefix(NotchMetrics.maxRings))
    }

    /// CoreGraphics rects are bottom-left origin; SwiftUI's `.position` is top-left and takes
    /// a centre. One conversion, in one place.
    private func centre(of rect: CGRect, in window: CGSize) -> CGPoint {
        CGPoint(x: rect.midX, y: window.height - rect.midY)
    }

    @ViewBuilder private var ringStack: some View {
        let models = rings
        let content = ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
            UsageRingView(model: model)
                .opacity(popoverIndex == nil || popoverIndex == index ? 1 : 0.55)
        }
        let gear = Button(action: onOpenDashboard) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: NotchMetrics.gearDiameter, height: NotchMetrics.gearDiameter)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Open Dashboard")

        if layout.placement.ringsAreVertical {
            VStack(spacing: NotchMetrics.ringSpacing) {
                if models.isEmpty { emptyNote } else { content }
                gear
            }
        } else {
            HStack(spacing: NotchMetrics.ringSpacing) {
                if models.isEmpty { emptyNote } else { content }
                gear
            }
        }
    }

    private var emptyNote: some View {
        Text("No accounts")
            .font(.caption2).foregroundStyle(.white.opacity(0.7))
            .frame(width: NotchMetrics.ringDiameter, height: NotchMetrics.ringDiameter)
    }

    public var body: some View {
        // 60s cadence: every relative time in the popover is minute-granular.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let models = rings
            let open = popoverIndex.flatMap { $0 < models.count ? $0 : nil }
            let frames = NotchGeometry.frames(
                layout: layout, expanded: expanded, ringCount: models.count,
                popover: open.map { (index: $0, windowCount: max(models[$0].windows.count, 1)) })

            ZStack(alignment: .topLeading) {
                Color.clear

                NotchShape(flushEdge: layout.placement.flushEdge)
                    .fill(.black)
                    .frame(width: frames.shape.width, height: frames.shape.height)
                    .overlay {
                        if expanded {
                            ringStack
                                .padding(.top, layout.placement.ringsAreVertical
                                         ? 0 : layout.collapsed.height + NotchMetrics.topGap)
                                .transition(.opacity)
                        }
                    }
                    .position(centre(of: frames.shape, in: frames.window))

                if let rect = frames.popover, let index = open {
                    NotchPopoverView(model: models[index], now: ctx.date)
                        .frame(width: rect.width, height: rect.height)
                        .position(centre(of: rect, in: frames.window))
                        .transition(.opacity)
                }
            }
            .frame(width: frames.window.width, height: frames.window.height, alignment: .topLeading)
            .animation(.spring(response: 0.30, dampingFraction: 0.80), value: expanded)
            .animation(.easeOut(duration: 0.12), value: open)
        }
    }
}
