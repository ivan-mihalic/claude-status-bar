// App/AppDelegate.swift
import AppKit
import ClaudeStatusBarApp

/// Applies the resting Dock-icon policy at launch. The app starts as an accessory
/// (LSUIElement) app; if the user enabled "Show icon in Dock", flip to `.regular`
/// once launched. Also wires up the window-close observer that returns the app to
/// accessory when the Dock icon is meant to stay hidden.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        DockController.shared.configure(showDock: showDock)
    }
}
