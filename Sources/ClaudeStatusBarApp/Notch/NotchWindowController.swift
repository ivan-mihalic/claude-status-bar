// Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift
import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: creates it when the setting is on, tears it down when off, rebuilds
/// it when the placement changes or the display configuration does (unplugging a monitor,
/// a resolution change, closing the lid).
///
/// All hover decisions are made here from raw pointer positions, because the panel lives in a
/// non-key window of a background app — the one place SwiftUI's own hover tracking is silent.
@MainActor
@Observable
public final class NotchWindowController {
    private let env: AppEnvironment
    /// Opens the Dashboard. Injected because `openWindow` only exists inside the SwiftUI
    /// scene graph, and this panel lives outside it.
    public var onOpenDashboard: () -> Void

    private var panel: NotchPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var layout: NotchLayout?
    private var expanded = false
    private var popoverIndex: Int?
    private var enabled = false
    private var placement: NotchPlacement = .topCenter
    private var edgeOffsetPercent: Double = 50

    public init(env: AppEnvironment, onOpenDashboard: @escaping () -> Void = {}) {
        self.env = env
        self.onOpenDashboard = onOpenDashboard
    }

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? build() : teardown()
    }

    /// Placement and edge height come from Settings; a change rebuilds the window, because
    /// its size and screen anchor both depend on them.
    public func setPlacement(_ placement: NotchPlacement, edgeOffsetPercent: Double) {
        guard placement != self.placement || edgeOffsetPercent != self.edgeOffsetPercent else { return }
        self.placement = placement
        self.edgeOffsetPercent = edgeOffsetPercent
        rebuild()
    }

    /// Rebuild against the current screens and settings. Idempotent — call it freely.
    public func rebuild() {
        guard enabled else { return }
        teardown()
        enabled = true
        build()
    }

    private var ringCount: Int { min(env.appState.accounts.count, NotchMetrics.maxRings) }

    private func build() {
        guard let screen = NSScreen.main else { return }
        let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen),
                                          placement: placement,
                                          edgeOffsetPercent: edgeOffsetPercent)
        self.layout = layout
        let windowSize = NotchMetrics.windowSize(placement: placement,
                                                 collapsed: layout.collapsed.size,
                                                 ringCount: ringCount)
        let frame = layout.panelFrame(expandedSize: windowSize)

        let panel = NotchPanel(frame: frame)
        let host = NotchHostingView(rootView: rootView())
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        host.onMouseMoved = { [weak self] point in self?.pointerMoved(to: point) }
        panel.contentView = host
        applyState(to: host)
        panel.orderFrontRegardless()      // show without activating the app
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
    }

    private func teardown() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
        layout = nil
        expanded = false
        popoverIndex = nil
        enabled = false
    }

    private func rootView() -> NotchRootView {
        NotchRootView(env: env,
                      layout: layout ?? NotchGeometry.layout(for: ScreenMetrics(
                        frame: .zero, topInset: 0, auxiliaryTopLeftWidth: nil)),
                      expanded: expanded, popoverIndex: popoverIndex,
                      onOpenDashboard: { [weak self] in self?.onOpenDashboard() })
    }

    /// One pointer position in, one panel state out.
    private func pointerMoved(to point: CGPoint?) {
        guard let panel, let layout,
              let host = panel.contentView as? NotchHostingView<NotchRootView> else { return }

        let frames = currentFrames()
        var nextExpanded = false
        var nextPopover: Int?

        if let point {
            let inShape = NotchShape(flushEdge: layout.placement.flushEdge)
                .cgPath(in: frames.shape).contains(point)
            // The popover keeps the panel open while the pointer is on it — including the
            // gap crossed on the way there, or it would close under the pointer mid-travel.
            let inPopover = frames.popover
                .map { $0.insetBy(dx: -NotchMetrics.popoverGap, dy: -NotchMetrics.popoverGap)
                        .contains(point) } ?? false
            nextExpanded = inShape || inPopover
            if nextExpanded {
                nextPopover = inPopover
                    ? popoverIndex
                    : NotchGeometry.ringIndex(at: point, layout: layout,
                                              shape: frames.shape, ringCount: ringCount)
            }
        }

        guard nextExpanded != expanded || nextPopover != popoverIndex else { return }
        expanded = nextExpanded
        popoverIndex = nextPopover
        host.rootView = rootView()
        applyState(to: host)
    }

    private func currentFrames() -> NotchFrames {
        guard let layout else {
            return NotchFrames(window: .zero, shape: .zero, popover: nil)
        }
        let models = NotchModel.rings(accounts: env.appState.accounts)
        let index = popoverIndex.flatMap { $0 < models.count ? $0 : nil }
        return NotchGeometry.frames(
            layout: layout, expanded: expanded, ringCount: ringCount,
            popover: index.map { (index: $0, windowCount: max(models[$0].windows.count, 1)) })
    }

    /// Keeps the clickable region equal to the drawn region: both come from
    /// `NotchGeometry.frames`, so they cannot disagree.
    private func applyState(to host: NotchHostingView<NotchRootView>) {
        guard let layout else { return }
        let frames = currentFrames()
        let path = CGMutablePath()
        path.addPath(NotchShape(flushEdge: layout.placement.flushEdge).cgPath(in: frames.shape))
        if let popover = frames.popover {
            path.addRect(popover.insetBy(dx: -NotchMetrics.popoverGap,
                                         dy: -NotchMetrics.popoverGap))
        }
        host.interactivePath = path
    }
}
