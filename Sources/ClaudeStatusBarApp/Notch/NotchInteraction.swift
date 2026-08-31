// Sources/ClaudeStatusBarApp/Notch/NotchInteraction.swift
import CoreGraphics

/// What the pointer is over, in the panel's window coordinates.
public enum NotchPointerState: Equatable, Sendable {
    /// Not on anything we drew. The window must let the click through to whatever is below.
    case away
    case onPanel(ringIndex: Int?)
    case onPopover

    public var isInteractive: Bool { self != .away }

    public var ringIndex: Int? {
        if case .onPanel(let index) = self { return index }
        return nil
    }
}

/// Turns a pointer position into what the panel should do about it.
///
/// This exists as a pure function because it answers the question that caused the worst bug
/// in this feature: *does the panel want this click?* A window whose `hitTest` returns `nil`
/// still swallows the event — hit-testing only chooses a view inside the window, it does not
/// pass anything to the window below. The only way a floating panel lets a click through is
/// `ignoresMouseEvents`, and that is a whole-window switch that has to be flipped from the
/// pointer position, every time it moves.
public enum NotchInteraction {
    public static func state(pointInWindow point: CGPoint?, layout: NotchLayout,
                             frames: NotchFrames, ringCount: Int) -> NotchPointerState {
        guard let point else { return .away }

        // The popover wins: it overlaps nothing, but the gap between it and the panel has to
        // count as "still on it" or it closes under the pointer on the way there.
        if let popover = frames.popover,
           popover.insetBy(dx: -NotchMetrics.popoverGap, dy: -NotchMetrics.popoverGap)
            .contains(point) {
            return .onPopover
        }

        let expanded = frames.shape.size != layout.collapsed.size
        guard NotchShape(flushEdge: layout.placement.flushEdge)
            .cgPath(in: frames.shape).contains(point) else { return .away }

        return .onPanel(ringIndex: NotchGeometry.ringIndex(at: point, layout: layout,
                                                           shape: frames.shape,
                                                           ringCount: ringCount,
                                                           expanded: expanded))
    }
}

/// Keeps the panel where it belongs.
///
/// `NSWindow.isMovable = false` only stops the *user* dragging a window; a window manager
/// (Magnet, Rectangle, Yabai…) sets the position through the Accessibility API, which does
/// not consult that flag. So the panel watches its own frame and puts itself back.
public enum NotchWindowGuard {
    /// Ignore drift below this: backing-scale rounding must not start a restore/notify loop
    /// with the window server.
    public static let tolerance: CGFloat = 0.5

    public static func needsRestore(current: CGRect, expected: CGRect) -> Bool {
        abs(current.minX - expected.minX) > tolerance
            || abs(current.minY - expected.minY) > tolerance
            || abs(current.width - expected.width) > tolerance
            || abs(current.height - expected.height) > tolerance
    }
}
