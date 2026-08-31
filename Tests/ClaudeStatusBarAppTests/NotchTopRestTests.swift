import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

// A 1710×1107 screen with a 38pt-tall, 256pt-wide cutout — the shape a notched Mac reports.
private let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                                    topInset: 38, auxiliaryTopLeftWidth: 727)
// An external display: no cutout at all.
private let external = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     topInset: 0, auxiliaryTopLeftWidth: nil)

private func top(_ m: ScreenMetrics, rings: Int, atRest: Bool) -> NotchLayout {
    NotchGeometry.layout(for: m, placement: .topCenter, ringCount: rings,
                         showRingsAtRest: atRest)
}

@Test func onlyARealCutoutReservesSpace() {
    // The whole point of the setting: pixels behind a hardware notch do not exist, so content
    // has to start below it. An external display has no such hole and must not be padded as
    // if it did.
    #expect(top(notched, rings: 3, atRest: true).notchClearance == 38)
    #expect(top(external, rings: 3, atRest: true).notchClearance == 0)
    #expect(top(notched, rings: 3, atRest: true).kind == .hardware)
    #expect(top(external, rings: 3, atRest: true).kind == .synthetic)
}

@Test func restingRingsSitBelowTheCutoutOnANotchedMac() {
    let layout = top(notched, rings: 3, atRest: true)
    let frames = NotchGeometry.frames(layout: layout, expanded: false, ringCount: 3, popover: nil)
    let first = layout.ringCentre(index: 0, in: frames.shape, expanded: false)
    let ringTop = first.y + NotchMetrics.collapsedRingDiameter / 2
    // Entirely clear of the cutout, which occupies the top 38pt of the screen.
    #expect(ringTop <= frames.shape.maxY - 38)
}

@Test func restingRingsSitAtTheTopOnAnExternalDisplay() {
    let layout = top(external, rings: 3, atRest: true)
    let frames = NotchGeometry.frames(layout: layout, expanded: false, ringCount: 3, popover: nil)
    let first = layout.ringCentre(index: 0, in: frames.shape, expanded: false)
    let gapAbove = frames.shape.maxY - (first.y + NotchMetrics.collapsedRingDiameter / 2)
    // Just the panel's own padding — no phantom cutout allowance.
    #expect(gapAbove == NotchMetrics.collapsedPadding)
}

@Test func aNotchedPanelIsTallerThanAnExternalOneForTheSameRings() {
    let n = top(notched, rings: 3, atRest: true).collapsed
    let e = top(external, rings: 3, atRest: true).collapsed
    #expect(n.height > e.height)
    // Exactly the cutout: the padding either side of the rings is identical on both screens.
    #expect(n.height - e.height == 38)
}

@Test func restingTopPanelIsSizedForItsRings() {
    let one = top(external, rings: 1, atRest: true).collapsed
    let four = top(external, rings: 4, atRest: true).collapsed
    #expect(four.width > one.width)          // a row, so it grows sideways
    #expect(four.height == one.height)
}

@Test func withoutTheSetting_theTopPanelStillHidesAtRest() {
    // Default behaviour is unchanged: the panel is the bare cutout (or pill) until hovered.
    #expect(top(notched, rings: 3, atRest: false).collapsed.height == 38)
    #expect(top(notched, rings: 3, atRest: false).collapsed.width == 256)
    #expect(top(external, rings: 3, atRest: false).collapsed.size == NotchMetrics.syntheticTopSize)
}

@Test func restingTopPanelIsAtLeastAsWideAsTheCutoutItHides() {
    // One ring is narrower than a 256pt notch; the panel must still cover the cutout, or a
    // strip of it shows either side of the panel.
    #expect(top(notched, rings: 1, atRest: true).collapsed.width >= 256)
}

@Test func expandedRingsClearTheCutoutToo() {
    for atRest in [true, false] {
        let layout = top(notched, rings: 2, atRest: atRest)
        let frames = NotchGeometry.frames(layout: layout, expanded: true, ringCount: 2,
                                          popover: nil)
        let first = layout.ringCentre(index: 0, in: frames.shape, expanded: true)
        #expect(first.y + NotchMetrics.ringDiameter / 2 <= frames.shape.maxY - 38)
    }
}
