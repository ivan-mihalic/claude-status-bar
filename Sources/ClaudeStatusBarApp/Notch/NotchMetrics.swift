// Sources/ClaudeStatusBarApp/Notch/NotchMetrics.swift
import CoreGraphics

/// Every dimension the panel is built from, in one place.
///
/// The drawn size, the clickable region and the popover position are all computed from these
/// numbers on purpose: derived twice, they drift, and the symptom is a panel that looks right
/// but eats clicks (or ignores them) along an invisible edge.
///
/// Two sizes exist for everything, because an edge panel shows its rings at rest (there is no
/// hardware cutout to hide in) and only grows them on hover.
public enum NotchMetrics {
    public static let ringDiameter: CGFloat = 46
    public static let collapsedRingDiameter: CGFloat = 24
    public static let ringSpacing: CGFloat = 14
    public static let collapsedRingSpacing: CGFloat = 8
    public static let padding: CGFloat = 14
    public static let collapsedPadding: CGFloat = 9
    /// Gap between a hardware notch (which we must not draw inside) and the first ring.
    public static let topGap: CGFloat = 8

    public static func ringDiameter(expanded: Bool) -> CGFloat {
        expanded ? ringDiameter : collapsedRingDiameter
    }
    public static func ringSpacing(expanded: Bool) -> CGFloat {
        expanded ? ringSpacing : collapsedRingSpacing
    }
    public static func padding(expanded: Bool) -> CGFloat {
        expanded ? padding : collapsedPadding
    }

    /// Resting pill where there is no hardware cutout and nothing to show — the top
    /// placement on a notchless screen, and an edge panel with no accounts yet.
    public static let syntheticTopSize = CGSize(width: 180, height: 32)
    public static let syntheticEdgeSize = CGSize(width: 32, height: 90)

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

    // MARK: Panel

    /// Length of the ring stack along the panel's long axis. The gear only exists when the
    /// panel is open; at rest an edge panel is just its rings.
    public static func stackLength(ringCount: Int, expanded: Bool) -> CGFloat {
        let n = CGFloat(min(max(ringCount, 0), maxRings))
        let d = ringDiameter(expanded: expanded)
        let gap = ringSpacing(expanded: expanded)
        let body = n == 0 ? d : n * d + max(n - 1, 0) * gap
        return expanded ? body + gap + gearDiameter : body
    }

    public static let gearDiameter: CGFloat = 34

    /// Resting size of an edge panel: it shows its rings, so it grows with the account count.
    public static func edgeCollapsedSize(ringCount: Int) -> CGSize {
        guard ringCount > 0 else { return syntheticEdgeSize }
        let thickness = collapsedRingDiameter + 2 * collapsedPadding
        let length = stackLength(ringCount: ringCount, expanded: false) + 2 * collapsedPadding
        return CGSize(width: thickness, height: length)
    }

    /// Vertical space the content must leave free at the top of a top-placed panel.
    ///
    /// This is the whole hardware-versus-external distinction in one number: the pixels
    /// behind a real cutout do not exist, so content starts below it. A display without one
    /// gets ordinary padding — reserving notch-sized space there would just look like a bug.
    public static func contentTopOffset(notchClearance: CGFloat, expanded: Bool) -> CGFloat {
        notchClearance > 0 ? notchClearance + topGap : padding(expanded: expanded)
    }

    /// Resting size of a top-placed panel that shows its rings. Without that setting the
    /// panel is just the cutout (or the pill) and this is not used.
    public static func topCollapsedSize(notchSize: CGSize, notchClearance: CGFloat,
                                        ringCount: Int) -> CGSize {
        let row = stackLength(ringCount: ringCount, expanded: false) + 2 * collapsedPadding
        let height = contentTopOffset(notchClearance: notchClearance, expanded: false)
            + collapsedRingDiameter + collapsedPadding
        // Only a real cutout sets a floor: the panel must cover it, or a strip of the notch
        // shows either side. On a display without one the panel is simply as big as its rings.
        guard notchClearance > 0 else { return CGSize(width: row, height: height) }
        return CGSize(width: max(row, notchSize.width), height: max(height, notchSize.height))
    }

    public static func expandedSize(placement: NotchPlacement, collapsed: CGSize,
                                    ringCount: Int, notchClearance: CGFloat = 0) -> CGSize {
        let content = stackLength(ringCount: ringCount, expanded: true) + 2 * padding
        if placement.ringsAreVertical {
            // Never smaller than the resting panel, or it would poke out from under the
            // panel that is supposed to have grown out of it.
            return CGSize(width: max(ringDiameter + 2 * padding, collapsed.width),
                          height: max(content, collapsed.height))
        }
        let height = contentTopOffset(notchClearance: notchClearance, expanded: true)
            + ringDiameter + padding
        return CGSize(width: max(content, collapsed.width),
                      height: max(height, collapsed.height))
    }

    /// Window big enough for the expanded panel *and* its popover, whichever way it opens.
    public static func windowSize(placement: NotchPlacement, collapsed: CGSize,
                                  ringCount: Int, notchClearance: CGFloat = 0) -> CGSize {
        let panel = expandedSize(placement: placement, collapsed: collapsed,
                                 ringCount: ringCount, notchClearance: notchClearance)
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
