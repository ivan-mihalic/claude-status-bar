// Sources/ClaudeStatusBarApp/Notch/NotchMetrics.swift
import CoreGraphics

/// Every dimension the panel is built from, in one place.
///
/// The drawn size, the clickable region and the popover position are all computed from these
/// numbers on purpose: derived twice, they drift, and the symptom is a panel that looks right
/// but eats clicks (or ignores them) along an invisible edge.
public enum NotchMetrics {
    public static let ringDiameter: CGFloat = 46
    public static let ringSpacing: CGFloat = 14
    public static let gearDiameter: CGFloat = 34
    public static let padding: CGFloat = 12
    /// Gap between a hardware notch (which we must not draw inside) and the first ring.
    public static let topGap: CGFloat = 8

    /// Resting pill on screens/edges with no hardware cutout to hide in.
    public static let syntheticTopSize = CGSize(width: 180, height: 32)
    public static let syntheticEdgeSize = CGSize(width: 32, height: 180)

    /// How many rings are drawn before the rest are dropped.
    public static let maxRings = 6

    // MARK: Popover

    public static let popoverWidth: CGFloat = 300
    public static let popoverGap: CGFloat = 8
    private static let popoverTitleHeight: CGFloat = 30
    private static let popoverRowHeight: CGFloat = 52
    private static let popoverPadding: CGFloat = 14

    public static func popoverHeight(windowCount: Int) -> CGFloat {
        popoverTitleHeight + CGFloat(max(windowCount, 1)) * popoverRowHeight + 2 * popoverPadding
    }

    /// Tallest popover we will ever draw: session + weekly + two premium windows.
    public static let maxPopoverHeight = popoverHeight(windowCount: 4)

    // MARK: Expanded panel

    /// Length of the ring stack along the panel's long axis, gear included.
    private static func stackLength(ringCount: Int) -> CGFloat {
        let n = CGFloat(min(max(ringCount, 0), maxRings))
        let rings = n * ringDiameter + max(n - 1, 0) * ringSpacing
        // With no accounts the stack is just the "no accounts" note, sized like one ring.
        let body = n == 0 ? ringDiameter : rings
        return body + ringSpacing + gearDiameter
    }

    public static func expandedSize(placement: NotchPlacement,
                                   collapsed: CGSize, ringCount: Int) -> CGSize {
        let content = stackLength(ringCount: ringCount) + 2 * padding
        if placement.ringsAreVertical {
            // Never shorter than the resting pill, or the pill pokes out from under the
            // panel that is supposed to have grown out of it.
            return CGSize(width: max(ringDiameter + 2 * padding, collapsed.width),
                          height: max(content, collapsed.height))
        }
        // Under the notch the content must clear the hardware cutout.
        return CGSize(width: max(content, collapsed.width),
                      height: max(collapsed.height + topGap + ringDiameter + padding,
                                  collapsed.height))
    }

    /// Window big enough for the expanded panel *and* its popover, whichever way it opens.
    public static func windowSize(placement: NotchPlacement, collapsed: CGSize,
                                  ringCount: Int) -> CGSize {
        let panel = expandedSize(placement: placement, collapsed: collapsed, ringCount: ringCount)
        switch placement {
        case .topCenter:
            return CGSize(width: max(panel.width, popoverWidth + 2 * popoverGap),
                          height: panel.height + popoverGap + maxPopoverHeight)
        case .leftEdge, .rightEdge:
            return CGSize(width: panel.width + popoverGap + popoverWidth,
                          height: max(panel.height, maxPopoverHeight + 2 * popoverGap))
        }
    }
}
