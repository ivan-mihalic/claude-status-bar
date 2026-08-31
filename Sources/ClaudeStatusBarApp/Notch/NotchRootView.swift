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

    /// The rings, at whichever size the current state calls for. An edge panel keeps them
    /// on show at rest — there is no hardware cutout to hide in, so an empty black bar would
    /// just be a black bar.
    @ViewBuilder private func ringStack(expanded: Bool) -> some View {
        let models = rings
        let content = ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
            UsageRingView(model: model,
                          diameter: NotchMetrics.ringDiameter(expanded: expanded))
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

        let spacing = NotchMetrics.ringSpacing(expanded: expanded)
        if layout.placement.ringsAreVertical {
            VStack(spacing: spacing) {
                if models.isEmpty { emptyNote(expanded: expanded) } else { content }
                if expanded { gear }
            }
        } else {
            HStack(spacing: spacing) {
                if models.isEmpty { emptyNote(expanded: expanded) } else { content }
                if expanded { gear }
            }
        }
    }

    @ViewBuilder private func emptyNote(expanded: Bool) -> some View {
        let d = NotchMetrics.ringDiameter(expanded: expanded)
        if expanded {
            Text("No accounts")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                .frame(width: d, height: d)
        } else {
            Image(systemName: "gauge.medium")
                .font(.system(size: d * 0.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: d, height: d)
        }
    }

    /// At rest the top placement shows nothing (it is hiding in the notch); an edge panel
    /// shows its rings.
    private var showsRingsAtRest: Bool { layout.placement.isEdge }

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
                        if expanded || showsRingsAtRest {
                            ringStack(expanded: expanded)
                                .padding(.top, layout.placement.ringsAreVertical
                                         ? 0 : layout.collapsed.height + NotchMetrics.topGap)
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
