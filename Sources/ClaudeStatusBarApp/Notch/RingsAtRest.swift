// Sources/ClaudeStatusBarApp/Notch/RingsAtRest.swift
import Foundation

/// Whether the resting top panel shows its rings — answered separately for a screen with a
/// hardware cutout and one without.
///
/// One switch could not serve both, because the two screens want opposite things from the
/// same person. On a MacBook alone the panel hides *inside* the notch and showing the rings
/// means giving up that trick; on an external display there is no cutout to hide in, so the
/// resting panel is a black pill either way and hiding the rings only makes it emptier.
/// Anyone working on the laptop and then plugging in a monitor was toggling this by hand
/// every time.
///
/// Which value applies is decided per panel, from the screen it is being built for, so
/// plugging a display in switches it without anyone touching a setting.
public struct RingsAtRest: Equatable, Sendable {
    public var onNotchedDisplay: Bool
    public var onPlainDisplay: Bool

    public init(onNotchedDisplay: Bool = false, onPlainDisplay: Bool = false) {
        self.onNotchedDisplay = onNotchedDisplay
        self.onPlainDisplay = onPlainDisplay
    }

    /// Both on — what a caller means by a plain `showRingsAtRest: true`.
    public static let always = RingsAtRest(onNotchedDisplay: true, onPlainDisplay: true)
    public static let never = RingsAtRest()

    public func value(hasNotch: Bool) -> Bool {
        hasNotch ? onNotchedDisplay : onPlainDisplay
    }
}

/// The one-time move from a single "keep the rings visible" switch to one per kind of display.
///
/// Kept as a pure decision plus a thin `apply`, because the thing that must not happen is a
/// second run overwriting whatever the user has since chosen — and that is exactly the part
/// that cannot be checked by looking at it.
public enum NotchSettingsMigration {
    public static let legacyKey = "notchShowRingsAtRestOnTop"
    public static let notchedKey = "notchRingsAtRestOnNotchedDisplay"
    public static let plainKey = "notchRingsAtRestOnPlainDisplay"

    /// - Returns: what to write, or `nil` when there is nothing to do — either because there
    ///   was no old setting, or because the new ones already exist.
    public static func migrate(legacy: Bool?, notched: Bool?,
                               plain: Bool?) -> (notched: Bool, plain: Bool)? {
        guard let legacy else { return nil }
        guard notched == nil, plain == nil else { return nil }
        // The old switch meant "on the top placement, wherever it is", so both screens
        // inherit it and nobody's panel changes appearance on upgrade.
        return (legacy, legacy)
    }

    public static func apply(to defaults: UserDefaults) {
        func stored(_ key: String) -> Bool? {
            defaults.object(forKey: key) as? Bool
        }
        guard let result = migrate(legacy: stored(legacyKey),
                                   notched: stored(notchedKey),
                                   plain: stored(plainKey)) else { return }
        defaults.set(result.notched, forKey: notchedKey)
        defaults.set(result.plain, forKey: plainKey)
        // Removed so this cannot run twice and so the old key stops being a second,
        // silently ignored source of truth.
        defaults.removeObject(forKey: legacyKey)
    }
}
