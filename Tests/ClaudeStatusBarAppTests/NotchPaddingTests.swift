import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

private let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                                    topInset: 38, auxiliaryTopLeftWidth: 727)
private let external = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     topInset: 0, auxiliaryTopLeftWidth: nil)

/// Space left above the rings, over and above any hardware cutout, and below them.
private func padding(_ m: ScreenMetrics, rings: Int = 3, atRest: Bool = false)
    -> (top: CGFloat, bottom: CGFloat, clearance: CGFloat) {
    let layout = NotchGeometry.layout(for: m, placement: .topCenter, ringCount: rings,
                                      showRingsAtRest: atRest)
    let size = NotchMetrics.expandedSize(placement: .topCenter, collapsed: layout.collapsed.size,
                                         ringCount: rings,
                                         notchClearance: layout.notchClearance)
    let top = layout.contentTopOffset(expanded: true) - layout.notchClearance
    let bottom = size.height - layout.contentTopOffset(expanded: true) - NotchMetrics.ringDiameter
    return (top, bottom, layout.notchClearance)
}

@Test func topAndBottomPaddingMatch_onADisplayWithoutANotch() {
    let p = padding(external)
    #expect(p.clearance == 0)
    #expect(p.top == p.bottom)
    #expect(p.top == NotchMetrics.padding)
}

@Test func aNotchedDisplayAddsTheCutoutOnTopOfTheSamePadding() {
    // The cutout is extra clearance, not a different layout: below it, the panel breathes
    // exactly as it does on any other screen.
    let p = padding(notched)
    #expect(p.clearance == 38)
    #expect(p.top == p.bottom)
    #expect(p.top == NotchMetrics.padding)
}

@Test func theRestingPanelUsesItsOwnMatchedPadding() {
    for screen in [external, notched] {
        let layout = NotchGeometry.layout(for: screen, placement: .topCenter, ringCount: 3,
                                          showRingsAtRest: true)
        let top = layout.contentTopOffset(expanded: false) - layout.notchClearance
        let bottom = layout.collapsed.height - layout.contentTopOffset(expanded: false)
            - NotchMetrics.collapsedRingDiameter
        #expect(top == NotchMetrics.collapsedPadding)
        #expect(bottom == top)
    }
}

@Test func theFirstRingIsCentredInTheSpaceTheLayoutClaims() {
    // Drawing and hit-testing both derive from contentTopOffset; if they ever disagree the
    // popover opens for a ring the pointer is not on.
    let layout = NotchGeometry.layout(for: notched, placement: .topCenter, ringCount: 3)
    let frames = NotchGeometry.frames(layout: layout, expanded: true, ringCount: 3, popover: nil)
    let centre = layout.ringCentre(index: 0, in: frames.shape, expanded: true)
    let gapAbove = frames.shape.maxY - (centre.y + NotchMetrics.ringDiameter / 2)
    #expect(gapAbove == layout.notchClearance + NotchMetrics.padding)
}
