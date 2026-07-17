import AppKit
import Sparkle

/// Sparkle's standard update windows/alerts would otherwise stay hidden behind other apps
/// in an accessory (LSUIElement, menu-bar-only) app. Per Sparkle's "gentle reminders" guide,
/// bring the app to the foreground when Sparkle is about to show update UI so the user
/// actually sees (and can act on) it.
final class UpdaterUIDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
