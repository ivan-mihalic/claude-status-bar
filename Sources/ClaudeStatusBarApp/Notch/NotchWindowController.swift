// Sources/ClaudeStatusBarApp/Notch/NotchWindowController.swift
import AppKit
import SwiftUI
import Observation

/// Owns the notch panels: creates them when the setting is on, tears them down when off, and
/// rebuilds them when the placement, the chosen display or the display configuration changes.
///
/// **The window is only as big as what is drawn in it.** At rest it is exactly the resting
/// panel; it grows to hold the open panel and its popover, and shrinks back when the pointer
/// leaves. That is what lets hover come from an `NSTrackingArea` instead of a global mouse
/// monitor: with no transparent margin around the panel there is nothing to make transparent
/// to clicks, so the window can keep accepting mouse events and be told when the pointer
/// arrives — rather than this process being woken on every pointer move anywhere on screen.
///
/// The one thing given up for that: at rest the window is the shape's bounding box, so the
/// few pixels in its rounded corners no longer pass clicks through to the desktop.
@MainActor
@Observable
public final class NotchWindowController {
    /// One panel on one screen, with its own hover state: two displays each get a panel, and
    /// only the one under the pointer reacts.
    private final class Instance {
        let panel: NotchPanel
        let host: NotchHostingView<NotchRootView>
        var layout: NotchLayout
        /// Size of the window while the panel is open — big enough for panel plus popover.
        let openWindowSize: CGSize
        let restingFrame: CGRect
        let openFrame: CGRect
        /// Whichever of the two the window currently has. Also the early-out rect: a pointer
        /// outside it cannot be on the panel.
        var currentFrame: CGRect
        var expanded = false
        /// Whether the *window* is currently the open one. Tracked apart from `expanded`
        /// because the two disagree for the length of the closing animation, and pairing
        /// collapsed content with a collapsed window size while the window is still open
        /// draws the panel against that window's edge instead of where it belongs.
        var windowIsOpen = false
        var popoverIndex: Int?
        /// What the pointer last asked for. Kept apart from `expanded` because opening takes
        /// two turns, and a pointer that leaves inside that gap has to be able to cancel it.
        var target: (expanded: Bool, index: Int?) = (false, nil)
        /// Pending shrink-back, so a reopen inside the closing animation cancels it.
        var shrink: DispatchWorkItem?
        /// Pending second half of an open (see `setExpanded`).
        var pendingOpen: DispatchWorkItem?

        init(panel: NotchPanel, host: NotchHostingView<NotchRootView>, layout: NotchLayout,
             openWindowSize: CGSize, restingFrame: CGRect, openFrame: CGRect) {
            self.panel = panel; self.host = host
            self.layout = layout; self.openWindowSize = openWindowSize
            self.restingFrame = restingFrame; self.openFrame = openFrame
            self.currentFrame = restingFrame
        }

        var windowSize: CGSize {
            NotchWindowController.contentWindowSize(windowIsOpen: windowIsOpen,
                                                    open: openWindowSize,
                                                    resting: layout.collapsed.size)
        }
    }

    private let env: AppEnvironment
    /// Opens the Dashboard. Injected because `openWindow` only exists inside the SwiftUI
    /// scene graph, and these panels live outside it.
    public var onOpenDashboard: () -> Void

    private var instances: [Instance] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var frameObserver: (any NSObjectProtocol)?
    /// Runs only while a panel is open. `mouseExited` is the normal way a panel closes; this
    /// is the backstop for the times it never arrives — a Space switch, a pointer warped by
    /// another app, a display waking up. Without it a missed exit leaves the panel open for
    /// good, which is a worse failure than half a wakeup per second while hovering.
    private var openWatchdog: Timer?

    private var enabled = false
    private var placement: NotchPlacement = .topCenter
    private var edgeOffsetPercent: Double = 50
    private var ringsAtRest = RingsAtRest()
    private var display: NotchDisplay = .mainDisplay
    private var expandOnHover = true
    private var showPopover = true
    private var screensAsleep = false

    /// Size the panel's content must be laid out for.
    ///
    /// It follows the **window**, not the panel state. On the way out the content collapses
    /// first and the window catches up when the animation is over; laying the collapsed shape
    /// out for a collapsed window during that gap puts it at the open window's leading edge —
    /// the panel visibly jumps sideways by half the difference between the two widths and
    /// snaps back. Measured at 77 px on a recording before this was split in two.
    public nonisolated static func contentWindowSize(windowIsOpen: Bool, open: CGSize,
                                                     resting: CGSize) -> CGSize {
        windowIsOpen ? open : resting
    }

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
                             ringsAtRest: RingsAtRest, display: NotchDisplay) {
        guard placement != self.placement
                || edgeOffsetPercent != self.edgeOffsetPercent
                || ringsAtRest != self.ringsAtRest
                || display != self.display else { return }
        self.placement = placement
        self.edgeOffsetPercent = edgeOffsetPercent
        self.ringsAtRest = ringsAtRest
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

    /// A sleeping or locked screen means nobody is looking at the panel. Ordering it out
    /// takes it off the compositor entirely and takes its tracking area with it; nothing is
    /// rebuilt, so waking is a single `orderFrontRegardless`.
    public func setScreensAsleep(_ asleep: Bool) {
        guard asleep != screensAsleep else { return }
        screensAsleep = asleep
        guard enabled else { return }
        if asleep {
            collapseAll()
            instances.forEach { $0.panel.orderOut(nil) }
        } else {
            instances.forEach { $0.panel.orderFrontRegardless() }
        }
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

    // MARK: Counting, without building anything

    /// How many rings are drawn. Deliberately not `NotchModel.rings(...).count`: that builds a
    /// `RingModel` per account, and this is asked on every pointer event.
    private var ringCount: Int {
        var count = 0
        for account in env.appState.accounts where account.isShownInNotch { count += 1 }
        return min(count, NotchMetrics.maxRings)
    }

    /// Number of usage windows on the nth visible account — the popover's height. Same
    /// reason as `ringCount`: counting beats building.
    private func windowCount(atRing index: Int) -> Int {
        var seen = 0
        for account in env.appState.accounts where account.isShownInNotch {
            if seen == index {
                guard let snapshot = account.lastSnapshot else { return 1 }
                return max(2 + snapshot.weekPremium.count, 1)
            }
            seen += 1
        }
        return 1
    }

    // MARK: Lifecycle

    private func build() {
        for screen in NotchScreens.screens(for: display) {
            let layout = NotchGeometry.layout(for: NotchGeometry.metrics(of: screen),
                                              placement: placement,
                                              edgeOffsetPercent: edgeOffsetPercent,
                                              ringCount: ringCount,
                                              ringsAtRest: ringsAtRest)
            let openWindowSize = NotchMetrics.windowSize(placement: placement,
                                                         collapsed: layout.collapsed.size,
                                                         ringCount: ringCount,
                                                         notchClearance: layout.notchClearance)
            let openFrame = layout.panelFrame(expandedSize: openWindowSize)
            let restingFrame = NotchGeometry.collapsedWindowFrame(
                layout: layout, expandedFrame: openFrame, windowSize: openWindowSize)

            let panel = NotchPanel(frame: restingFrame)
            let host = NotchHostingView(rootView: rootView(layout: layout, expanded: false,
                                                           popoverIndex: nil,
                                                           windowSize: layout.collapsed.size))
            host.frame = CGRect(origin: .zero, size: restingFrame.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            // The resting window *is* the panel, so there is no transparent margin to make
            // click-through — and the window has to keep accepting events or its tracking
            // area would never fire.
            panel.ignoresMouseEvents = false

            let instance = Instance(panel: panel, host: host, layout: layout,
                                    openWindowSize: openWindowSize,
                                    restingFrame: restingFrame, openFrame: openFrame)
            host.onPointerInside = { [weak self, weak instance] in
                guard let self, let instance else { return }
                MainActor.assumeIsolated { self.update(instance) }
            }
            host.onPointerExited = { [weak self, weak instance] in
                guard let self, let instance else { return }
                MainActor.assumeIsolated { self.setExpanded(instance, false, popoverIndex: nil) }
            }
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
    }

    private func teardown() {
        [screenObserver, frameObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        screenObserver = nil; frameObserver = nil
        setOpenWatchdog(false)
        instances.forEach { $0.shrink?.cancel(); $0.pendingOpen?.cancel(); $0.panel.orderOut(nil) }
        instances = []
        enabled = false
    }

    private func rootView(layout: NotchLayout, expanded: Bool, popoverIndex: Int?,
                          windowSize: CGSize) -> NotchRootView {
        NotchRootView(env: env, layout: layout, expanded: expanded, popoverIndex: popoverIndex,
                      windowSize: windowSize,
                      onOpenDashboard: { [weak self] in self?.onOpenDashboard() })
    }

    // MARK: Pointer

    /// Re-reads the pointer for every panel. Only used where there is no event to go on:
    /// a settings change, and the open-panel watchdog.
    private func reevaluatePointer() {
        for instance in instances { update(instance) }
    }

    private func collapseAll() {
        for instance in instances where instance.expanded {
            setExpanded(instance, false, popoverIndex: nil)
        }
    }

    /// One pointer position in, one panel state out.
    private func update(_ instance: Instance) {
        let screenPoint = NSEvent.mouseLocation
        // Four comparisons before anything is computed. A pointer that is not on this window
        // and a panel that is not open have nothing to decide.
        guard instance.expanded || instance.currentFrame.contains(screenPoint) else { return }

        let origin = instance.currentFrame.origin
        let inWindow = instance.currentFrame.contains(screenPoint)
            ? CGPoint(x: screenPoint.x - origin.x, y: screenPoint.y - origin.y)
            : nil

        let count = ringCount
        let frames = self.frames(for: instance, ringCount: count)
        let state = NotchInteraction.state(pointInWindow: inWindow, layout: instance.layout,
                                           frames: frames, ringCount: count)
        let decision = NotchInteraction.decide(state: state, current: instance.popoverIndex,
                                               expandOnHover: expandOnHover,
                                               showPopover: showPopover, ringCount: count)
        // `decision.acceptsMouse` is deliberately not consulted here any more. It is true for
        // exactly the pointer positions that keep the panel open, and the window only has
        // margins to give away while it is open — so acting on `expanded` covers it, and
        // flipping the window transparent to clicks mid-close would stop it noticing the
        // pointer coming back.
        setExpanded(instance, decision.expanded, popoverIndex: decision.popoverIndex)
    }

    /// Applies a new panel state, resizing the window around it.
    ///
    /// Opening takes **two turns** and that is not incidental. SwiftUI animates a change only
    /// when the geometry it animates *into* already holds; moving the window and expanding the
    /// panel in one transaction gives it a new coordinate space and a new size at once, and it
    /// re-lays out instead of animating. Measured on a recording: the panel went from resting
    /// to full height in a single frame on the way open, against five frames on the way
    /// closed. So the window is adopted first with the panel still drawn at rest — which puts
    /// nothing anywhere new on screen — and the expansion follows on the next turn, with only
    /// `expanded` changing. It then grows away from whichever edge it is flush with: down from
    /// the top, right from the left edge, left from the right edge.
    ///
    /// Closing needs none of that: the window stays open until the shape has finished
    /// shrinking, so there is only ever one thing changing.
    private func setExpanded(_ instance: Instance, _ expanded: Bool, popoverIndex: Int?) {
        let index = expanded ? popoverIndex : nil
        guard (expanded, index) != instance.target else { return }
        instance.target = (expanded, index)

        instance.pendingOpen?.cancel(); instance.pendingOpen = nil
        instance.shrink?.cancel();      instance.shrink = nil

        if expanded, !instance.windowIsOpen {
            adoptOpenWindow(instance)
            let work = DispatchWorkItem { [weak self, weak instance] in
                guard let self, let instance else { return }
                MainActor.assumeIsolated {
                    instance.pendingOpen = nil
                    self.render(instance, expanded: instance.target.expanded,
                                index: instance.target.index)
                }
            }
            instance.pendingOpen = work
            DispatchQueue.main.async(execute: work)
        } else {
            render(instance, expanded: expanded, index: index)
            if !expanded, instance.windowIsOpen { scheduleShrink(instance) }
        }

        setOpenWatchdog(instances.contains { $0.windowIsOpen })
    }

    /// Grows the window to its open size while the panel is still drawn at rest. Nothing moves
    /// on screen: the resting shape sits in the same place in either window, which is what
    /// `closingPanel_doesNotJumpSideways` pins down.
    private func adoptOpenWindow(_ instance: Instance) {
        // `currentFrame` first: it is what the frame guard compares against, so moving the
        // window before updating it would look like a window manager did it.
        instance.windowIsOpen = true
        instance.currentFrame = instance.openFrame
        instance.panel.setFrame(instance.openFrame, display: false)
        render(instance, expanded: instance.expanded, index: instance.popoverIndex)
    }

    private func render(_ instance: Instance, expanded: Bool, index: Int?) {
        instance.expanded = expanded
        instance.popoverIndex = index
        instance.host.rootView = rootView(layout: instance.layout, expanded: expanded,
                                          popoverIndex: index,
                                          windowSize: instance.windowSize)
        apply(instance)
    }

    /// Puts the window back to the resting size once the closing animation has finished. The
    /// window keeps taking mouse events throughout, so the pointer coming back cancels this.
    private func scheduleShrink(_ instance: Instance) {
        let work = DispatchWorkItem { [weak self, weak instance] in
            guard let self, let instance else { return }
            MainActor.assumeIsolated {
                instance.windowIsOpen = false
                instance.currentFrame = instance.restingFrame
                instance.panel.setFrame(instance.restingFrame, display: false)
                // Re-laid out for the window it now actually has. By this point the shape is
                // already at its resting size, so nothing moves.
                self.render(instance, expanded: false, index: nil)
                self.setOpenWatchdog(self.instances.contains { $0.windowIsOpen })
            }
        }
        instance.shrink = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NotchAnimation.finish(container: true, expanding: false)
                + NotchAnimation.settleMargin,
            execute: work)
    }

    private func setOpenWatchdog(_ on: Bool) {
        guard on != (openWatchdog != nil) else { return }
        openWatchdog?.invalidate()
        openWatchdog = nil
        guard on else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluatePointer() }
        }
        // Apple asks for a tolerance on every repeating timer so macOS can fire it next to
        // whatever else is already waking the CPU.
        timer.tolerance = 0.2
        openWatchdog = timer
    }

    private func frames(for instance: Instance, ringCount count: Int) -> NotchFrames {
        let index = instance.popoverIndex.flatMap { $0 < count ? $0 : nil }
        return NotchGeometry.frames(
            layout: instance.layout, expanded: instance.expanded, ringCount: count,
            popover: index.map { (index: $0, windowCount: windowCount(atRing: $0)) },
            windowSize: instance.windowSize)
    }

    /// Keeps the clickable region equal to the drawn region: both come from
    /// `NotchGeometry.frames`, so they cannot disagree.
    private func apply(_ instance: Instance) {
        let frames = self.frames(for: instance, ringCount: ringCount)
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
                                            expected: instance.currentFrame) else { return }
        instance.panel.setFrame(instance.currentFrame, display: false)
    }
}
