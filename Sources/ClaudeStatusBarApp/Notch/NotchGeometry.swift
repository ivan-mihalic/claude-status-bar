// Sources/ClaudeStatusBarApp/Notch/NotchGeometry.swift
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Everything the layout needs to know about a screen, lifted out of `NSScreen` so the
/// math is testable without a display attached (the dev machine has no notch).
public struct ScreenMetrics: Equatable, Sendable {
    /// `NSScreen.frame` — bottom-left origin, in points.
    public let frame: CGRect
    /// `NSScreen.safeAreaInsets.top`. 0 on a screen with no notch.
    public let topInset: CGFloat
    /// Width of `NSScreen.auxiliaryTopLeftArea` — the usable strip left of the notch.
    /// `nil` when the screen reports no such area.
    public let auxiliaryTopLeftWidth: CGFloat?

    public init(frame: CGRect, topInset: CGFloat, auxiliaryTopLeftWidth: CGFloat?) {
        self.frame = frame; self.topInset = topInset
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
    }
}

public enum NotchKind: Equatable, Sendable {
    /// A real hardware notch; the collapsed panel hides inside it.
    case hardware
    /// No notch on this screen — we draw a pill over the top of the menu bar instead.
    case synthetic
}

public struct NotchLayout: Equatable, Sendable {
    public let kind: NotchKind
    /// Resting rect, screen coordinates, bottom-left origin, flush with the screen top.
    public let collapsed: CGRect
    public let screen: CGRect

    public init(kind: NotchKind, collapsed: CGRect, screen: CGRect) {
        self.kind = kind; self.collapsed = collapsed; self.screen = screen
    }

    /// The window frame. The panel is *always* this size — expansion happens inside it,
    /// so no window ever moves or resizes while the pointer is over it.
    public func panelFrame(expandedSize: CGSize) -> CGRect {
        let width = min(max(expandedSize.width, collapsed.width), screen.width)
        let height = min(max(expandedSize.height, collapsed.height), screen.height)
        var x = collapsed.midX - width / 2
        x = min(max(x, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
}

public enum NotchGeometry {
    /// Size of the fake notch drawn on screens that have none.
    public static let syntheticCollapsedSize = CGSize(width: 180, height: 32)

    public static func layout(for m: ScreenMetrics) -> NotchLayout {
        if m.topInset > 0, let aux = m.auxiliaryTopLeftWidth, aux > 0 {
            let width = m.frame.width - 2 * aux
            if width > 0 {
                let rect = CGRect(x: m.frame.midX - width / 2,
                                  y: m.frame.maxY - m.topInset,
                                  width: width, height: m.topInset)
                return NotchLayout(kind: .hardware, collapsed: rect, screen: m.frame)
            }
        }
        let size = syntheticCollapsedSize
        let rect = CGRect(x: m.frame.midX - size.width / 2,
                          y: m.frame.maxY - size.height,
                          width: size.width, height: size.height)
        return NotchLayout(kind: .synthetic, collapsed: rect, screen: m.frame)
    }

    #if canImport(AppKit)
    /// Reads the live values. `auxiliaryTopLeftArea` is `NSRect?` in Swift (macOS 12+) and is
    /// `nil` on screens with no notch — verified against the macOS 27.0 SDK on 2026-08-31.
    @MainActor
    public static func metrics(of screen: NSScreen) -> ScreenMetrics {
        ScreenMetrics(frame: screen.frame,
                      topInset: screen.safeAreaInsets.top,
                      auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width)
    }
    #endif
}
