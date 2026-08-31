import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

// Illustrative numbers, not a claim about any specific Mac: a 1710×1107 point screen
// whose menu-bar area is 38pt tall and whose usable top-left region is 727pt wide,
// leaving 1710 − 2×727 = 256pt of notch.
private let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                                    topInset: 38, auxiliaryTopLeftWidth: 727)
private let plain = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                  topInset: 0, auxiliaryTopLeftWidth: nil)

@Test func hardwareNotch_isDerivedFromTheAuxiliaryArea() {
    let layout = NotchGeometry.layout(for: notched)
    #expect(layout.kind == .hardware)
    #expect(layout.collapsed.width == 256)
    #expect(layout.collapsed.height == 38)
    // Horizontally centred, and flush with the top edge (bottom-left origin!).
    #expect(layout.collapsed.midX == 855)
    #expect(layout.collapsed.maxY == 1107)
}

@Test func screenWithoutNotch_getsASyntheticPill() {
    let layout = NotchGeometry.layout(for: plain)
    #expect(layout.kind == .synthetic)
    #expect(layout.collapsed.size == NotchGeometry.syntheticCollapsedSize)
    #expect(layout.collapsed.midX == 960)
    #expect(layout.collapsed.maxY == 1080)
}

@Test func missingAuxiliaryWidth_fallsBackToSynthetic() {
    // A top inset with no auxiliary area is a shape we cannot measure; guessing a
    // width here would silently mis-place the panel, so treat it as no notch.
    let odd = ScreenMetrics(frame: plain.frame, topInset: 38, auxiliaryTopLeftWidth: nil)
    #expect(NotchGeometry.layout(for: odd).kind == .synthetic)
}

@Test func panelFrame_isCentredOnTheNotchAndClampedToTheScreen() {
    let layout = NotchGeometry.layout(for: notched)
    let frame = layout.panelFrame(expandedSize: CGSize(width: 400, height: 300))
    #expect(frame.midX == layout.collapsed.midX)
    #expect(frame.maxY == 1107)
    #expect(frame.width == 400)

    // Wider than the screen → clamped, never hanging off the edge.
    let huge = layout.panelFrame(expandedSize: CGSize(width: 5000, height: 300))
    #expect(huge.width == 1710)
    #expect(huge.minX == 0)
}

@Test func panelFrame_neverSmallerThanTheCollapsedNotch() {
    let layout = NotchGeometry.layout(for: notched)
    let frame = layout.panelFrame(expandedSize: CGSize(width: 10, height: 10))
    #expect(frame.width >= layout.collapsed.width)
    #expect(frame.height >= layout.collapsed.height)
}
