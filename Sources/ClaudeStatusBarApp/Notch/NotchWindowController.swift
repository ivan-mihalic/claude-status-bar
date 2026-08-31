// Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift
import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: creates it when the setting is on, tears it down when off, and
/// rebuilds it when the display configuration changes (unplugging a monitor, a resolution
/// change, closing the lid).
@MainActor
@Observable
public final class NotchWindowController {
    private let env: AppEnvironment
    /// Opens the Dashboard. Injected because `openWindow` only exists inside the SwiftUI
    /// scene graph, and this panel lives outside it.
    public var onOpenDashboard: () -> Void

    private var panel: NotchPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var expanded = false
    private var enabled = false

    public init(env: AppEnvironment, onOpenDashboard: @escaping () -> Void = {}) {
        self.env = env
        self.onOpenDashboard = onOpenDashboard
    }

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? build() : teardown()
    }

    /// Rebuild against the current screens. Idempotent — call it freely.
    public func refreshForScreens() { if enabled { teardown(); enabled = true; build() } }

    private var currentLayout: NotchLayout? {
        guard let screen = panel?.screen ?? NSScreen.main else { return nil }
        return NotchGeometry.layout(for: NotchGeometry.metrics(of: screen))
    }

    private func build() {
        guard let screen = NSScreen.main else { return }
        let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen))
        let frame = layout.panelFrame(expandedSize: NotchMetrics.panelSize)

        let panel = NotchPanel(frame: frame)
        let host = NotchHostingView(rootView: rootView(layout: layout, expanded: false))
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        host.onHoverInsideShape = { [weak self] inside in self?.setExpanded(inside) }
        panel.contentView = host
        updateInteractivePath(host: host, layout: layout, size: frame.size)
        panel.orderFrontRegardless()      // show without activating the app
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshForScreens() }
            }
    }

    private func teardown() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
        expanded = false
        enabled = false
    }

    private func rootView(layout: NotchLayout, expanded: Bool) -> NotchRootView {
        NotchRootView(env: env, layout: layout, expanded: expanded,
                      onOpenDashboard: { [weak self] in self?.onOpenDashboard() })
    }

    private func setExpanded(_ on: Bool) {
        guard on != expanded, let panel,
              let host = panel.contentView as? NotchHostingView<NotchRootView>,
              let layout = currentLayout else { return }
        expanded = on
        host.rootView = rootView(layout: layout, expanded: on)
        updateInteractivePath(host: host, layout: layout, size: panel.frame.size)
    }

    /// Keeps the clickable region equal to the drawn region — both come from `NotchShape`
    /// and `NotchMetrics`, so they cannot disagree.
    private func updateInteractivePath(host: NotchHostingView<NotchRootView>,
                                       layout: NotchLayout, size: CGSize) {
        let ringCount = min(env.appState.accounts.count, NotchMetrics.maxRings)
        let width = expanded ? NotchMetrics.expandedWidth : layout.collapsed.width
        let height = expanded
            ? NotchMetrics.expandedHeight(collapsedHeight: layout.collapsed.height,
                                          ringCount: ringCount)
            : layout.collapsed.height
        let rect = CGRect(x: (size.width - width) / 2, y: size.height - height,
                          width: width, height: height)
        host.interactivePath = NotchShape().cgPath(in: rect)
    }
}
