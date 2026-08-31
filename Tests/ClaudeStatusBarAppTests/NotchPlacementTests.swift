import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let plain = ScreenMetrics(frame: screen, topInset: 0, auxiliaryTopLeftWidth: nil)

private func layout(_ p: NotchPlacement, offset: Double = 50) -> NotchLayout {
    NotchGeometry.layout(for: plain, placement: p, edgeOffsetPercent: offset)
}

@Test func edgePlacements_sitFlushAgainstTheirOwnEdge() {
    #expect(layout(.leftEdge).collapsed.minX == screen.minX)
    #expect(layout(.rightEdge).collapsed.maxX == screen.maxX)
    // An edge pill is tall and thin, the opposite of the top one.
    #expect(layout(.leftEdge).collapsed.size == NotchMetrics.syntheticEdgeSize)
}

@Test func edgeOffset_runsFromTopToBottom() {
    // 0 % = top of the screen, 100 % = bottom. Anything else and the slider reads backwards.
    #expect(layout(.leftEdge, offset: 0).collapsed.maxY == screen.maxY)
    #expect(layout(.leftEdge, offset: 100).collapsed.minY == screen.minY)
    #expect(layout(.leftEdge, offset: 50).collapsed.midY == screen.midY)
}

@Test func nonsenseOffset_parksAtAnEdgeInsteadOfOffScreen() {
    #expect(layout(.rightEdge, offset: -500).collapsed.maxY == screen.maxY)
    #expect(layout(.rightEdge, offset: 9999).collapsed.minY == screen.minY)
}

@Test func topPlacement_ignoresTheOffset() {
    #expect(layout(.topCenter, offset: 0).collapsed == layout(.topCenter, offset: 90).collapsed)
}

@Test func ringsRunAcrossTheShortAxis() {
    #expect(NotchPlacement.topCenter.ringsAreVertical == false)
    #expect(NotchPlacement.leftEdge.ringsAreVertical)
    #expect(NotchPlacement.rightEdge.ringsAreVertical)
}

@Test func expandedPanel_growsAlongTheRingAxis() {
    let top = NotchMetrics.expandedSize(placement: .topCenter,
                                        collapsed: NotchMetrics.syntheticTopSize, ringCount: 3)
    let topOne = NotchMetrics.expandedSize(placement: .topCenter,
                                           collapsed: NotchMetrics.syntheticTopSize, ringCount: 1)
    #expect(top.width > topOne.width)
    #expect(top.height == topOne.height)          // a row gets wider, not taller

    let side = NotchMetrics.expandedSize(placement: .leftEdge,
                                         collapsed: NotchMetrics.syntheticEdgeSize, ringCount: 3)
    let sideOne = NotchMetrics.expandedSize(placement: .leftEdge,
                                            collapsed: NotchMetrics.syntheticEdgeSize, ringCount: 1)
    #expect(side.height > sideOne.height)         // a column gets taller, not wider
    #expect(side.width == sideOne.width)
}

// MARK: Popover placement

private func frames(_ p: NotchPlacement, ringIndex: Int = 0, rings: Int = 3) -> NotchFrames {
    NotchGeometry.frames(layout: layout(p), expanded: true, ringCount: rings,
                         popover: (index: ringIndex, windowCount: 3))
}

@Test func popover_opensOnTheSideThePanelIsNotAttachedTo() {
    let top = frames(.topCenter)
    #expect(top.popover!.maxY <= top.shape.minY)          // below the notch

    let left = frames(.leftEdge)
    #expect(left.popover!.minX >= left.shape.maxX)        // to the right of a left panel

    let right = frames(.rightEdge)
    #expect(right.popover!.maxX <= right.shape.minX)      // to the left of a right panel
}

@Test func popover_linesUpWithTheRingBeingHovered() {
    let first = frames(.leftEdge, ringIndex: 0)
    let third = frames(.leftEdge, ringIndex: 2)
    // Rings run top-down, so a later ring's popover sits lower.
    #expect(third.popover!.midY < first.popover!.midY)
}

@Test func popover_staysInsideItsWindow() {
    for placement in NotchPlacement.allCases {
        for index in 0..<6 {
            let f = frames(placement, ringIndex: index, rings: 6)
            let p = f.popover!
            #expect(p.minX >= -0.001)
            #expect(p.minY >= -0.001)
            #expect(p.maxX <= f.window.width + 0.001)
            #expect(p.maxY <= f.window.height + 0.001)
        }
    }
}

@Test func collapsedPanel_hasNoPopoverEvenIfOneIsRequested() {
    let f = NotchGeometry.frames(layout: layout(.topCenter), expanded: false, ringCount: 2,
                                 popover: (index: 0, windowCount: 3))
    #expect(f.popover == nil)
    #expect(f.shape.size == layout(.topCenter).collapsed.size)
}

// MARK: Rings visible at rest on the edges

@Test func edgePanel_atRestIsSizedForItsRings() {
    // The edge panel shows its rings without being hovered, so its resting size has to grow
    // with the account count — unlike the top one, which hides in the notch.
    let one = NotchGeometry.layout(for: plain, placement: .leftEdge, ringCount: 1).collapsed
    let four = NotchGeometry.layout(for: plain, placement: .leftEdge, ringCount: 4).collapsed
    #expect(four.height > one.height)
    #expect(four.width == one.width)
    // No accounts: nothing to show, so it falls back to a plain stub.
    #expect(NotchGeometry.layout(for: plain, placement: .leftEdge, ringCount: 0).collapsed.size
            == NotchMetrics.syntheticEdgeSize)
}

@Test func topPanel_atRestIgnoresTheRingCount() {
    let one = NotchGeometry.layout(for: plain, placement: .topCenter, ringCount: 1).collapsed
    let four = NotchGeometry.layout(for: plain, placement: .topCenter, ringCount: 4).collapsed
    #expect(one == four)
}

@Test func restingRingsAreSmallerThanOpenOnes() {
    #expect(NotchMetrics.ringDiameter(expanded: false) < NotchMetrics.ringDiameter(expanded: true))
    #expect(NotchMetrics.stackLength(ringCount: 3, expanded: false)
            < NotchMetrics.stackLength(ringCount: 3, expanded: true))
    // The gear only exists once the panel is open.
    #expect(NotchMetrics.stackLength(ringCount: 0, expanded: false)
            == NotchMetrics.collapsedRingDiameter)
}

@Test func ringHitTest_followsTheSizeCurrentlyDrawn() {
    // A pointer on the third resting ring must not be read against the open geometry, or
    // the wrong account's details open.
    let layout = NotchGeometry.layout(for: plain, placement: .leftEdge, ringCount: 4)
    let frames = NotchGeometry.frames(layout: layout, expanded: false, ringCount: 4, popover: nil)
    let third = layout.ringCentre(index: 2, in: frames.shape, expanded: false)
    #expect(NotchGeometry.ringIndex(at: third, layout: layout, shape: frames.shape,
                                   ringCount: 4, expanded: false) == 2)
    #expect(NotchGeometry.ringIndex(at: third, layout: layout, shape: frames.shape,
                                   ringCount: 4, expanded: true) != 2)
}
