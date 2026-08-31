// Sources/ClaudeStatusBarApp/Notch/NotchScreens.swift
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Which display the panel belongs on.
public enum NotchDisplay: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The display that carries the menu bar and the Dock.
    case mainDisplay
    /// The built-in panel with the hardware cutout, wherever it currently sits.
    case notchedDisplay
    /// One panel per display.
    case allDisplays

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mainDisplay:    return "Main display"
        case .notchedDisplay: return "Display with the notch"
        case .allDisplays:    return "All displays"
        }
    }

    public var detail: String {
        switch self {
        case .mainDisplay:
            return "The one with the menu bar and the Dock."
        case .notchedDisplay:
            return "The built-in screen on a MacBook that has a cutout. Falls back to the "
                 + "main display when no screen has one."
        case .allDisplays:
            return "A panel on every screen, each reacting to the pointer on its own."
        }
    }
}

public enum NotchScreens {
    /// Indices into `screens`, in the order panels should be created.
    ///
    /// Deliberately does **not** ask AppKit for `NSScreen.main`: that is the screen with the
    /// *active window*, which for a menu-bar app with no key window is wherever the user last
    /// clicked. It put the panel on an external monitor and drew a synthetic pill there while
    /// the real notch sat unused on the built-in display.
    public static func choose(_ screens: [ScreenMetrics], mode: NotchDisplay) -> [Int] {
        guard !screens.isEmpty else { return [] }
        switch mode {
        case .allDisplays:
            return Array(screens.indices)
        case .mainDisplay:
            return [mainIndex(screens)]
        case .notchedDisplay:
            return [screens.firstIndex(where: hasNotch) ?? mainIndex(screens)]
        }
    }

    /// The display carrying the menu bar always sits at the global origin; AppKit's screen
    /// ordering is not otherwise guaranteed, so the origin is the thing to test for.
    public static func mainIndex(_ screens: [ScreenMetrics]) -> Int {
        screens.firstIndex { $0.frame.origin == .zero } ?? 0
    }

    public static func hasNotch(_ m: ScreenMetrics) -> Bool {
        m.topInset > 0 && (m.auxiliaryTopLeftWidth ?? 0) > 0
    }

    #if canImport(AppKit)
    @MainActor
    public static func screens(for mode: NotchDisplay) -> [NSScreen] {
        let all = NSScreen.screens
        let metrics = all.map(NotchGeometry.metrics(of:))
        return choose(metrics, mode: mode).compactMap { all.indices.contains($0) ? all[$0] : nil }
    }
    #endif
}
