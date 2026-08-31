// Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift
import AppKit
import SwiftUI
import Observation

/// Owns the notch panels: creates them when the setting is on, tears them down when off, and
/// rebuilds them when the placement, the chosen display or the display configuration changes.
///
/// All hover decisions are made here from raw pointer positions, because the panels live in
/// non-key windows of a background app — the one place SwiftUI's own hover tracking is silent.
@MainActor
@Observable
public final class NotchWindowController {
    /// One panel on one screen, with its own hover state: two displays each get a panel, and
    /// only the one under the pointer reacts.
    private final class Instance {
        let panel: NotchPanel
        let host: NotchHostingView<NotchRootView>
        var layout: NotchLayout
        var expectedFrame: CGRect
        var expanded = false
        var popoverIndex: Int?

        init(panel: NotchPanel, host: NotchHostingView<NotchRootView>,
             layout: NotchLayout, expectedFrame: CGRect) {
            self.panel = panel; self.host = host
            self.layout = layout; self.expectedFrame = expectedFrame
        }
    }

    private let env: AppEnvironment
    /// Opens the Dashboard. Injected because `openWindow` only exists inside the SwiftUI
    /// scene graph, and these panels live outside it.
    public var onOpenDashboard: () -> Void

    private var instances: [Instance] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var frameObserver: (any NSObjectProtocol)?
    private var mouseMonitors: [Any] = []
    private var pointerPoll: Timer?

    private var enabled = false
    private var placement: NotchPlacement = .topCenter
    private var edgeOffsetPercent: Double = 50
    private var showRingsAtRestOnTop = false
    private var display: NotchDisplay = .mainDisplay
    private var expandOnHover = true
    private var showPopover = true

    public init(env: AppEnvironment, onOpenDashboard: @escaping () -> Void = {}) {
        self.env = env
        self.onOpenDashboard = onOpenDashboard
    }

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? build() : teardown()
    }

    /// Placement, edge height and target display all change the windows themselves, so a
    /// change rebuilds rather than redraws.
    public func setPlacement(_ placement: NotchPlacement, edgeOffsetPercent: Double,
                             showRingsAtRestOnTop: Bool, display: NotchDisplay) {
        guard placement != self.placement
                || edgeOffsetPercent != self.edgeOffsetPercent
                || showRingsAtRestOnTop != self.showRingsAtRestOnTop
                || display != self.display else { return }
        self.placement = placement
        self.edgeOffsetPercent = edgeOffsetPercent
        self.showRingsAtRestOnTop = showRingsAtRestOnTop
        self.display = display
        rebuild()
    }

    /// Behaviour switches only change what a pointer move means, so nothing is rebuilt — but
    /// a panel already open under the pointer is re-evaluated, or the setting would appear
    /// not to take effect until the pointer next moved.
    public func setBehaviour(expandOnHover: Bool, showPopover: Bool) {
        guard expandOnHover != self.expandOnHover || showPopover != self.showPopover else { return }
        self.expandOnHover = expandOnHover
        self.showPopover = showPopover
        reevaluatePointer()
    }

    public func rebuild() {
        guard enabled else { return }
        teardown()
        enabled = true
        build()
    }

    /// The resting panel is sized from the visible ring count whenever it shows its rings, so
    /// adding, removing or hiding an account changes the windows themselves.
    public func accountsChanged() {
        guard enabled, instances.contains(where: { $0.layout.showsRingsAtRest }) else { return }
        rebuild()
    }

    private var ringCount: Int {
        min(NotchModel.rings(accounts: env.appState.accounts).count, NotchMetrics.maxRings)
    }

    // MARK: Lifecycle

    private func build() {
        for screen in NotchScreens.screens(for: display) {
            let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen),
                                              placement: placement,
                                              edgeOffsetPercent: edgeOffsetPercent,
                                              ringCount: ringCount,
                                              showRingsAtRest: showRingsAtRestOnTop)
            let windowSize = NotchMetrics.windowSize(placement: placement,
                                                     collapsed: layout.collapsed.size,
                                                     ringCount: ringCount,
                                                     notchClearance: layout.notchClearance)
            let frame = layout.panelFrame(expandedSize: windowSize)

            let panel = NotchPanel(frame: frame)
            let host = NotchHostingView(rootView: rootView(layout: layout, expanded: false,
                                                           popoverIndex: nil))
            host.frame = CGRect(origin: .zero, size: frame.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host

            let instance = Instance(panel: panel, host: host, layout: layout, expectedFrame: frame)
            apply(instance)
            panel.orderFrontRegardless()      // show without activating the app
            instances.append(instance)
        }
        guard !instances.isEmpty else { return }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }

        // A window manager moves or tiles a panel through the Accessibility API, which ignores
        // `isMovable = false`. Watching the frame is the only defence that works whoever did it.
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.restoreFrameIfMoved(note.object as? NSWindow) }
            }

        installMouseMonitors()
    }

    private func teardown() {
        [screenObserver, frameObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        screenObserver = nil; frameObserver = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        setPointerPolling(false)
        instances.forEach { $0.panel.orderOut(nil) }
        instances = []
        enabled = false
    }

    private func rootView(layout: NotchLayout, expanded: Bool, popoverIndex: Int?) -> NotchRootView {
        NotchRootView(env: env, layout: layout, expanded: expanded, popoverIndex: popoverIndex,
                      onOpenDashboard: { [weak self] in self?.onOpenDashboard() })
    }

    // MARK: Pointer

    /// The pointer has to be tracked even while the windows ignore mouse events — and they do,
    /// almost always, so that clicks reach the desktop instead of an invisible wall. A tracking
    /// area inside a window would therefore never fire.
    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluatePointer() }
        }
        // The global monitor is silent while our own app is frontmost, so pair it with a local
        // one; otherwise the panel freezes the moment its Dashboard window has focus.
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.reevaluatePointer() }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
    }

    /// While a panel is open the event monitors stop being a reliable source: with
    /// `ignoresMouseEvents` off the moves are delivered to *this* app, so the global monitor
    /// goes quiet, and the panel is not a key window, so the local one never sees a
    /// mouse-moved either. Reading the pointer directly does not depend on delivery at all.
    private func setPointerPolling(_ on: Bool) {
        guard on != (pointerPoll != nil) else { return }
        pointerPoll?.invalidate()
        pointerPoll = nil
        guard on else { return }
        pointerPoll = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluatePointer() }
        }
    }

    private func reevaluatePointer() {
        let point = NSEvent.mouseLocation
        for instance in instances { update(instance, screenPoint: point) }
        setPointerPolling(instances.contains { $0.expanded })
    }

    /// One pointer position in, one panel state out — including whether the window wants the
    /// click at all.
    private func update(_ instance: Instance, screenPoint: CGPoint) {
        let origin = instance.panel.frame.origin
        let inWindow = instance.panel.frame.contains(screenPoint)
            ? CGPoint(x: screenPoint.x - origin.x, y: screenPoint.y - origin.y)
            : nil

        let frames = self.frames(for: instance)
        let state = NotchInteraction.state(pointInWindow: inWindow, layout: instance.layout,
                                           frames: frames, ringCount: ringCount)
        let decision = NotchInteraction.decide(state: state, current: instance.popoverIndex,
                                               expandOnHover: expandOnHover,
                                               showPopover: showPopover, ringCount: ringCount)
        // The whole point: outside the drawn panel the window is transparent to clicks.
        instance.panel.ignoresMouseEvents = !decision.acceptsMouse

        guard decision.expanded != instance.expanded
                || decision.popoverIndex != instance.popoverIndex else { return }
        instance.expanded = decision.expanded
        instance.popoverIndex = decision.popoverIndex
        instance.host.rootView = rootView(layout: instance.layout, expanded: instance.expanded,
                                          popoverIndex: instance.popoverIndex)
        apply(instance)
    }

    private func frames(for instance: Instance) -> NotchFrames {
        let models = NotchModel.rings(accounts: env.appState.accounts)
        let index = instance.popoverIndex.flatMap { $0 < models.count ? $0 : nil }
        return NotchGeometry.frames(
            layout: instance.layout, expanded: instance.expanded, ringCount: ringCount,
            popover: index.map { (index: $0, windowCount: max(models[$0].windows.count, 1)) })
    }

    /// Keeps the clickable region equal to the drawn region: both come from
    /// `NotchGeometry.frames`, so they cannot disagree.
    private func apply(_ instance: Instance) {
        let frames = self.frames(for: instance)
        let path = CGMutablePath()
        path.addPath(NotchShape(flushEdge: instance.layout.placement.flushEdge)
            .cgPath(in: frames.shape))
        if let popover = frames.popover {
            path.addRect(popover.insetBy(dx: -NotchMetrics.popoverGap,
                                         dy: -NotchMetrics.popoverGap))
        }
        instance.host.interactivePath = path
    }

    private func restoreFrameIfMoved(_ window: NSWindow?) {
        guard let window,
              let instance = instances.first(where: { $0.panel === window }),
              NotchWindowGuard.needsRestore(current: instance.panel.frame,
                                            expected: instance.expectedFrame) else { return }
        instance.panel.setFrame(instance.expectedFrame, display: false)
    }
}
