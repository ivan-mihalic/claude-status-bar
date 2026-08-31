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
    private var frameObserver: (any NSObjectProtocol)?
    private var mouseMonitors: [Any] = []
    /// Where the panel belongs. Anything else is a window manager having opinions.
    private var expectedFrame: CGRect?
    private var layout: NotchLayout?
    private var expanded = false
    private var popoverIndex: Int?
    private var enabled = false
    private var placement: NotchPlacement = .topCenter
    private var edgeOffsetPercent: Double = 50
    private var expandOnHover = true
    private var showPopover = true
    private var showRingsAtRestOnTop = false

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
    public func setPlacement(_ placement: NotchPlacement, edgeOffsetPercent: Double,
                             showRingsAtRestOnTop: Bool) {
        guard placement != self.placement
                || edgeOffsetPercent != self.edgeOffsetPercent
                || showRingsAtRestOnTop != self.showRingsAtRestOnTop else { return }
        self.placement = placement
        self.edgeOffsetPercent = edgeOffsetPercent
        self.showRingsAtRestOnTop = showRingsAtRestOnTop
        rebuild()
    }

    /// Behaviour switches from the Notch Panel screen. These change what a pointer move
    /// means, not the window, so nothing is rebuilt — but a panel already open under the
    /// pointer is collapsed, or the setting would appear not to take effect until the
    /// pointer next moved.
    public func setBehaviour(expandOnHover: Bool, showPopover: Bool) {
        guard expandOnHover != self.expandOnHover || showPopover != self.showPopover else { return }
        self.expandOnHover = expandOnHover
        self.showPopover = showPopover
        reevaluatePointer()
    }

    /// Rebuild against the current screens and settings. Idempotent — call it freely.
    public func rebuild() {
        guard enabled else { return }
        teardown()
        enabled = true
        build()
    }

    /// Visible rings, not accounts: hiding an account changes the panel exactly as removing
    /// one does, and the count is what the resting edge panel is sized from.
    private var ringCount: Int {
        min(NotchModel.rings(accounts: env.appState.accounts).count, NotchMetrics.maxRings)
    }

    /// The resting edge panel is sized from the visible ring count, so adding, removing or
    /// hiding an account changes the window itself, not just what is drawn in it.
    public func accountsChanged() {
        guard enabled, let layout, layout.showsRingsAtRest else { return }
        rebuild()
    }

    private func build() {
        guard let screen = NSScreen.main else { return }
        let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen),
                                          placement: placement,
                                          edgeOffsetPercent: edgeOffsetPercent,
                                          ringCount: ringCount,
                                          showRingsAtRest: showRingsAtRestOnTop)
        self.layout = layout
        let windowSize = NotchMetrics.windowSize(placement: placement,
                                                 collapsed: layout.collapsed.size,
                                                 ringCount: ringCount,
                                                 notchClearance: layout.notchClearance)
        let frame = layout.panelFrame(expandedSize: windowSize)

        let panel = NotchPanel(frame: frame)
        let host = NotchHostingView(rootView: rootView())
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        applyState(to: host)
        panel.orderFrontRegardless()      // show without activating the app
        self.panel = panel
        self.expectedFrame = frame

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }

        // A window manager moves or tiles the panel through the Accessibility API, which
        // ignores `isMovable = false`. Watching the frame is the only defence that works
        // whoever did it.
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restoreFrameIfMoved() }
            }

        installMouseMonitors()
    }

    /// The pointer has to be tracked even while the window ignores mouse events — and it does,
    /// almost always, so that clicks reach the desktop instead of an invisible wall. A tracking
    /// area inside the window would therefore never fire.
    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(toScreenPoint: NSEvent.mouseLocation) }
        }
        // The global monitor is silent while our own app is frontmost, so pair it with a local
        // one; otherwise the panel freezes the moment its Dashboard window has focus.
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(toScreenPoint: NSEvent.mouseLocation) }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
    }

    private func restoreFrameIfMoved() {
        guard let panel, let expectedFrame,
              NotchWindowGuard.needsRestore(current: panel.frame, expected: expectedFrame)
        else { return }
        panel.setFrame(expectedFrame, display: false)
    }

    private func teardown() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        expectedFrame = nil
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

    /// One pointer position in, one panel state out — including whether the window wants the
    /// click at all. Everything else about hover flows from this.
    private func pointerMoved(toScreenPoint screenPoint: CGPoint) {
        guard let panel, let layout,
              let host = panel.contentView as? NotchHostingView<NotchRootView> else { return }

        // Screen coordinates → window coordinates. Both are bottom-left origin, so this is a
        // translation, not a flip.
        let origin = panel.frame.origin
        let raw = CGPoint(x: screenPoint.x - origin.x, y: screenPoint.y - origin.y)
        let inWindow = panel.frame.contains(screenPoint) ? raw : nil

        let frames = currentFrames()
        let state = NotchInteraction.state(pointInWindow: inWindow, layout: layout,
                                           frames: frames, ringCount: ringCount)

        // The whole point: outside the drawn panel the window is transparent to clicks.
        panel.ignoresMouseEvents = !state.isInteractive

        var nextExpanded = false
        var nextPopover: Int?
        if expandOnHover, state.isInteractive {
            nextExpanded = true
            if showPopover {
                nextPopover = state == .onPopover ? popoverIndex : state.ringIndex
            }
        }

        guard nextExpanded != expanded || nextPopover != popoverIndex else { return }
        expanded = nextExpanded
        popoverIndex = nextPopover
        host.rootView = rootView()
        applyState(to: host)
    }

    /// Used when a behaviour setting changes: re-evaluate against wherever the pointer is.
    private func reevaluatePointer() { pointerMoved(toScreenPoint: NSEvent.mouseLocation) }

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
