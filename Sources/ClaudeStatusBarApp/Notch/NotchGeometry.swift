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
    /// Nothing to hide in — we draw a pill against the screen edge instead.
    case synthetic
}

/// Drawing rects for one frame of the panel, all in the *window's* coordinate space
/// (bottom-left origin), so the view and the hit-test path cannot disagree.
public struct NotchFrames: Equatable, Sendable {
    public let window: CGSize
    public let shape: CGRect
    /// `nil` when no ring is being inspected.
    public let popover: CGRect?

    public init(window: CGSize, shape: CGRect, popover: CGRect?) {
        self.window = window; self.shape = shape; self.popover = popover
    }
}

public struct NotchLayout: Equatable, Sendable {
    public let kind: NotchKind
    public let placement: NotchPlacement
    /// Resting rect in screen coordinates, bottom-left origin, flush with its screen edge.
    public let collapsed: CGRect
    public let screen: CGRect

    public init(kind: NotchKind, placement: NotchPlacement,
                collapsed: CGRect, screen: CGRect) {
        self.kind = kind; self.placement = placement
        self.collapsed = collapsed; self.screen = screen
    }

    /// The window frame in screen coordinates. The window is fixed: expansion and the
    /// popover happen *inside* it, so nothing moves or resizes while the pointer is over it.
    public func panelFrame(expandedSize: CGSize) -> CGRect {
        let width = min(max(expandedSize.width, collapsed.width), screen.width)
        let height = min(max(expandedSize.height, collapsed.height), screen.height)
        switch placement {
        case .topCenter:
            var x = collapsed.midX - width / 2
            x = min(max(x, screen.minX), screen.maxX - width)
            return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
        case .leftEdge, .rightEdge:
            var y = collapsed.midY - height / 2
            y = min(max(y, screen.minY), screen.maxY - height)
            let x = placement == .leftEdge ? screen.minX : screen.maxX - width
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Where the panel body is drawn inside its window: flush with the screen edge, centred
    /// on the collapsed rect along the other axis.
    public func shapeRect(windowSize: CGSize, size: CGSize) -> CGRect {
        switch placement {
        case .topCenter:
            return CGRect(x: (windowSize.width - size.width) / 2,
                          y: windowSize.height - size.height,
                          width: size.width, height: size.height)
        case .leftEdge:
            return CGRect(x: 0, y: (windowSize.height - size.height) / 2,
                          width: size.width, height: size.height)
        case .rightEdge:
            return CGRect(x: windowSize.width - size.width,
                          y: (windowSize.height - size.height) / 2,
                          width: size.width, height: size.height)
        }
    }

    /// Centre of ring `index` inside `shape`, along the axis the rings run on.
    public func ringCentre(index: Int, in shape: CGRect) -> CGPoint {
        let step = NotchMetrics.ringDiameter + NotchMetrics.ringSpacing
        let lead = NotchMetrics.padding + NotchMetrics.ringDiameter / 2 + CGFloat(index) * step
        if placement.ringsAreVertical {
            return CGPoint(x: shape.midX, y: shape.maxY - lead)
        }
        // Under the notch the rings sit below the hardware cutout.
        let top = shape.maxY - collapsed.height - NotchMetrics.topGap - NotchMetrics.ringDiameter / 2
        return CGPoint(x: shape.minX + lead, y: top)
    }
}

public enum NotchGeometry {
    /// Kept for the top placement's synthetic pill; edges use `syntheticEdgeSize`.
    public static var syntheticCollapsedSize: CGSize { NotchMetrics.syntheticTopSize }

    /// - Parameter edgeOffsetPercent: 0 = top of the screen, 100 = bottom. Ignored for
    ///   `.topCenter`. Clamped, so a nonsense value parks the panel at an edge rather than
    ///   off-screen.
    public static func layout(for m: ScreenMetrics,
                              placement: NotchPlacement = .topCenter,
                              edgeOffsetPercent: Double = 50) -> NotchLayout {
        switch placement {
        case .topCenter:
            if m.topInset > 0, let aux = m.auxiliaryTopLeftWidth, aux > 0 {
                let width = m.frame.width - 2 * aux
                if width > 0 {
                    let rect = CGRect(x: m.frame.midX - width / 2,
                                      y: m.frame.maxY - m.topInset,
                                      width: width, height: m.topInset)
                    return NotchLayout(kind: .hardware, placement: placement,
                                       collapsed: rect, screen: m.frame)
                }
            }
            let size = NotchMetrics.syntheticTopSize
            let rect = CGRect(x: m.frame.midX - size.width / 2,
                              y: m.frame.maxY - size.height,
                              width: size.width, height: size.height)
            return NotchLayout(kind: .synthetic, placement: placement,
                               collapsed: rect, screen: m.frame)

        case .leftEdge, .rightEdge:
            let size = NotchMetrics.syntheticEdgeSize
            let p = min(max(edgeOffsetPercent, 0), 100) / 100
            let centreY = m.frame.maxY - p * m.frame.height
            let y = min(max(centreY - size.height / 2, m.frame.minY),
                        m.frame.maxY - size.height)
            let x = placement == .leftEdge ? m.frame.minX : m.frame.maxX - size.width
            return NotchLayout(kind: .synthetic, placement: placement,
                               collapsed: CGRect(x: x, y: y, width: size.width, height: size.height),
                               screen: m.frame)
        }
    }

    /// Everything that gets drawn, for one state of the panel.
    public static func frames(layout: NotchLayout, expanded: Bool, ringCount: Int,
                              popover: (index: Int, windowCount: Int)?) -> NotchFrames {
        let windowSize = NotchMetrics.windowSize(placement: layout.placement,
                                                 collapsed: layout.collapsed.size,
                                                 ringCount: ringCount)
        let size = expanded
            ? NotchMetrics.expandedSize(placement: layout.placement,
                                        collapsed: layout.collapsed.size, ringCount: ringCount)
            : layout.collapsed.size
        let shape = layout.shapeRect(windowSize: windowSize, size: size)

        guard expanded, let popover else {
            return NotchFrames(window: windowSize, shape: shape, popover: nil)
        }

        let w = NotchMetrics.popoverWidth
        let h = NotchMetrics.popoverHeight(windowCount: popover.windowCount)
        let centre = layout.ringCentre(index: popover.index, in: shape)
        let rect: CGRect
        switch layout.placement.popoverSide {
        case .below:
            let x = min(max(centre.x - w / 2, 0), windowSize.width - w)
            rect = CGRect(x: x, y: shape.minY - NotchMetrics.popoverGap - h, width: w, height: h)
        case .trailing:
            let y = min(max(centre.y - h / 2, 0), windowSize.height - h)
            rect = CGRect(x: shape.maxX + NotchMetrics.popoverGap, y: y, width: w, height: h)
        case .leading:
            let y = min(max(centre.y - h / 2, 0), windowSize.height - h)
            rect = CGRect(x: shape.minX - NotchMetrics.popoverGap - w, y: y, width: w, height: h)
        }
        return NotchFrames(window: windowSize, shape: shape, popover: rect)
    }

    /// Which ring the pointer is over, if any. Computed here rather than with SwiftUI's
    /// `.onHover` because the panel lives in a non-key window of a background app, where
    /// SwiftUI's hover tracking does not fire.
    public static func ringIndex(at point: CGPoint, layout: NotchLayout,
                                 shape: CGRect, ringCount: Int) -> Int? {
        guard ringCount > 0 else { return nil }
        // Half a gap of slack either side, so the gaps between rings belong to the nearer
        // one instead of closing the popover as the pointer slides down the stack.
        let reach = NotchMetrics.ringDiameter / 2 + NotchMetrics.ringSpacing / 2
        for index in 0..<min(ringCount, NotchMetrics.maxRings) {
            let c = layout.ringCentre(index: index, in: shape)
            let along = layout.placement.ringsAreVertical ? abs(point.y - c.y) : abs(point.x - c.x)
            let across = layout.placement.ringsAreVertical ? abs(point.x - c.x) : abs(point.y - c.y)
            if along <= reach && across <= NotchMetrics.ringDiameter / 2 + 4 { return index }
        }
        return nil
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
