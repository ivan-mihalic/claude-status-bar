// Sources/ClaudeStatusBarApp/Environment/ClickOutsideFocus.swift
import AppKit

/// Ends text editing when the user clicks anywhere that isn't a text field.
///
/// AppKit keeps a text field as the window's first responder until something else
/// claims it, and most controls (buttons, steppers) never do — so after typing in a
/// field it stays focused no matter where you click. This watches mouse-downs and
/// hands first responder back to the window when the click landed outside any
/// editable text, which is what "click away to deselect" means everywhere else.
@MainActor
public enum ClickOutsideFocus {
    private static var monitor: Any?

    /// Decides, for the view a click landed on, whether editing should end.
    /// Split out from the event plumbing so it can be tested directly.
    public static func shouldDismissEditing(clickedView: NSView?) -> Bool {
        var view = clickedView
        while let current = view {
            if let text = current as? NSTextView, text.isEditable { return false }
            if let field = current as? NSTextField, field.isEditable { return false }
            view = current.superview
        }
        return true
    }

    /// Installs the app-wide monitor. Safe to call more than once.
    public static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            guard let window = event.window,
                  // Only interfere while a field editor actually holds focus.
                  window.firstResponder is NSTextView else { return event }
            let hit = window.contentView?.hitTest(event.locationInWindow)
            if shouldDismissEditing(clickedView: hit) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }
}
