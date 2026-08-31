// Sources/ClaudeStatusBarApp/Notch/NotchPanel.swift
import AppKit
import SwiftUI

/// Hosting view whose hit-testing is clipped to the drawn shape.
///
/// This is the *second* line of defence, not the first. Hit-testing only picks a view inside
/// the window — a `nil` result still leaves the window swallowing the click, which is exactly
/// how an invisible wall forms around a transparent panel. Click-through is `ignoresMouseEvents`
/// on the window, driven by `NotchInteraction`; this clip just keeps stray events inside the
/// window off the SwiftUI content.
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Current opaque region, in CoreGraphics (bottom-left origin) coordinates of this view.
    public var interactivePath: CGPath?

    /// The pointer is inside this window, or has just left it.
    ///
    /// A tracking area is the one hover source that works here, and it is the reason this
    /// app no longer watches the mouse globally. The panel is a non-key window of a
    /// background app, so SwiftUI's `onHover` and a local event monitor are both silent —
    /// but `NSTrackingArea` with `.activeAlways` reports enter, move and exit regardless of
    /// key or active state, and it only fires when the pointer is actually here. A global
    /// monitor, by contrast, woke this process on every pointer move anywhere on screen.
    public var onPointerInside: (() -> Void)?
    public var onPointerExited: (() -> Void)?

    private var hoverArea: NSTrackingArea?

    public required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only ever removes the area this class installed: `NSHostingView` keeps its own for
        // SwiftUI hover, and tearing those out would break `.help` tooltips and button
        // highlighting inside the panel.
        if let hoverArea, trackingAreas.contains(hoverArea) { removeTrackingArea(hoverArea) }
        // `.inVisibleRect` keeps the area glued to the bounds, which matters because the
        // window is resized whenever the panel opens or closes.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .inVisibleRect,
                                            .mouseEnteredAndExited, .mouseMoved],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointerInside?()
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointerInside?()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerExited?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let path = interactivePath else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let p = isFlipped ? CGPoint(x: local.x, y: bounds.height - local.y)
                          : CGPoint(x: local.x, y: local.y)
        guard path.contains(p) else { return nil }
        return super.hitTest(point)
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
        // Starts transparent to clicks; the controller turns this off as soon as the panel is
        // on screen. It has to be off for the tracking area to ever fire — a window that
        // ignores mouse events is not told the pointer arrived — and it is safe to leave off
        // because the resting window is exactly the panel, with no transparent margin around
        // it to form an invisible wall over the desktop.
        ignoresMouseEvents = true
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
