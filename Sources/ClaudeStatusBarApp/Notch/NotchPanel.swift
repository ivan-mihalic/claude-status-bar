// Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift
import AppKit
import SwiftUI

/// Hosting view whose hit-testing and hover tracking are clipped to the drawn shape.
///
/// Without the clipping the panel's transparent margin swallows every click across the top
/// of the screen — and the symptom (menu-bar items that "stop working") points nowhere near
/// this file.
///
/// Hover is driven from AppKit rather than SwiftUI's `.onHover` on purpose: this panel lives
/// in a non-activating window of a background app, and only an `.activeAlways` tracking area
/// reports the pointer there.
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Current opaque region, in CoreGraphics (bottom-left origin) coordinates of this view.
    /// Set by the controller whenever the panel expands or collapses.
    public var interactivePath: CGPath?
    /// Called with the pointer position in this view's CoreGraphics (bottom-left origin)
    /// coordinates, or `nil` when the pointer leaves the window. The controller decides what
    /// that means — expand, collapse, or open a ring's popover.
    public var onMouseMoved: ((CGPoint?) -> Void)?

    private var tracking: NSTrackingArea?

    public required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Converts a point in this view's coordinates into the path's space, accounting for the
    /// flipped (top-left origin) geometry `NSHostingView` uses.
    private func pathPoint(_ local: NSPoint) -> CGPoint {
        isFlipped ? CGPoint(x: local.x, y: bounds.height - local.y) : CGPoint(x: local.x, y: local.y)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let path = interactivePath else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        guard path.contains(pathPoint(local)) else { return nil }
        return super.hitTest(point)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved,
                                            .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    public override func mouseEntered(with event: NSEvent) { report(event) }
    public override func mouseMoved(with event: NSEvent) { report(event) }
    public override func mouseExited(with event: NSEvent) { onMouseMoved?(nil) }

    private func report(_ event: NSEvent) {
        onMouseMoved?(pathPoint(convert(event.locationInWindow, from: nil)))
    }
}

/// Borderless, non-activating panel pinned above the menu bar.
public final class NotchPanel: NSPanel {
    public init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar                 // above the menu bar, below system alerts
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        // Present on every Space and over full-screen apps, without pulling the app forward.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    // A borderless panel is not key by default; without this the SwiftUI content can never
    // take a click. `.nonactivatingPanel` keeps the app itself in the background.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}
