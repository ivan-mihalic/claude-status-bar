// Sources/ClaudeStatusBarApp/DockController.swift
import AppKit

/// Central owner of the app's `NSApplication.ActivationPolicy`.
///
/// The app ships as an LSUIElement (accessory) menu-bar app with no Dock icon.
/// Two things complicate that:
///   1. A user setting can request a persistent Dock icon (`.regular`).
///   2. Even when the Dock icon is hidden, an accessory app must briefly become
///      `.regular` to actually present/key-focus a window (otherwise the window
///      never appears and its text fields reject keyboard input).
///
/// This controller keeps the *resting* policy in sync with the setting and, when
/// the Dock icon is meant to stay hidden, drops back to `.accessory` once the last
/// titled window closes — so opening a window doesn't strand a Dock icon forever.
@MainActor
public final class DockController: NSObject {
    public static let shared = DockController()

    /// Persisted user preference: show a Dock icon at rest.
    private var showDock = false
    private var observing = false

    private override init() { super.init() }

    /// Apply the resting policy at launch and start observing window closes.
    /// Call once from `applicationDidFinishLaunching`.
    public func configure(showDock: Bool) {
        self.showDock = showDock
        applyResting()
        if !observing {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: nil)
            observing = true
        }
    }

    /// React to the Settings toggle.
    public func setShowDock(_ on: Bool) {
        showDock = on
        // Turning it on shows the Dock icon immediately; turning it off drops to
        // accessory even if a window is still open (the window stays, the Dock icon
        // just disappears).
        NSApp.setActivationPolicy(on ? .regular : .accessory)
    }

    /// Become a regular, active app so an accessory app can show/focus a window.
    /// Call immediately before `openWindow(id:)`.
    public func prepareToShowWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyResting() {
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard !showDock else { return }
        let closing = note.object as? NSWindow
        // Defer so the closing window is gone before we count what's left. The menu
        // popover (MenuBarExtra) is borderless, so `.titled` filters it out.
        Task { @MainActor in
            let stillOpen = NSApp.windows.contains { win in
                win !== closing && win.isVisible && win.styleMask.contains(.titled)
            }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
