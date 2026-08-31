// Sources/ClaudeStatusBarApp/Notch/NotchMetrics.swift
import CoreGraphics

/// The panel's inner dimensions, in one place.
///
/// The drawn size and the clickable region are computed from the same numbers on purpose:
/// derived twice, they drift, and the symptom is a panel that looks right but eats clicks
/// (or ignores them) along an invisible edge.
public enum NotchMetrics {
    public static let expandedWidth: CGFloat = 220
    /// Vertical space one ring + its percentage occupies.
    public static let ringSlot: CGFloat = 72
    public static let gearSlot: CGFloat = 34
    /// Gap between the notch/pill and the first ring.
    public static let topGap: CGFloat = 10
    public static let bottomPadding: CGFloat = 14

    /// Window size. Fixed, and big enough for the largest panel we will draw, because the
    /// panel expands *inside* its window — the window itself never moves or resizes.
    public static let panelSize = CGSize(width: 300, height: 560)

    /// How many rings fit before the panel would overflow `panelSize`.
    public static let maxRings = 5

    public static func expandedHeight(collapsedHeight: CGFloat, ringCount: Int) -> CGFloat {
        let rings = CGFloat(min(max(ringCount, 1), maxRings))
        return collapsedHeight + topGap + rings * ringSlot + gearSlot + bottomPadding
    }
}
