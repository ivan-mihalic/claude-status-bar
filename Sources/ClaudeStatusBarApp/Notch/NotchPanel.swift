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

    public required init(rootView: Content) {
        super.init(rootView: rootView)
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
        // Starts transparent to clicks: the controller turns this off only while the pointer
        // is actually on the panel. Anything else is an invisible wall over the desktop.
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
