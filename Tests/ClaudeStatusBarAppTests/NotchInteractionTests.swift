import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

private let plain = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                  topInset: 0, auxiliaryTopLeftWidth: nil)

private func setup(_ placement: NotchPlacement, rings: Int = 3, expanded: Bool = false)
    -> (NotchLayout, NotchFrames) {
    let layout = NotchGeometry.layout(for: plain, placement: placement, ringCount: rings)
    let frames = NotchGeometry.frames(layout: layout, expanded: expanded, ringCount: rings,
                                      popover: nil)
    return (layout, frames)
}

// The reported bug: an invisible wall around the panel. A window whose hit-test returns nil
// still swallows the click — only `ignoresMouseEvents` lets it through — so the panel must
// know, for any pointer position, whether it wants the event at all.
@Test func pointerOutsideThePanel_isNotInteractive() {
    let (layout, frames) = setup(.leftEdge)
    // Far corner of the window: inside the window rect, nowhere near the drawn panel.
    let far = CGPoint(x: frames.window.width - 4, y: 4)
    let state = NotchInteraction.state(pointInWindow: far, layout: layout, frames: frames,
                                       ringCount: 3)
    #expect(state == .away)
    #expect(state.isInteractive == false)
}

@Test func everyPointOutsideTheShape_isNotInteractive() {
    // Sweep the whole window: the only interactive pixels are the ones we drew on.
    for placement in NotchPlacement.allCases {
        let (layout, frames) = setup(placement)
        let path = NotchShape(flushEdge: placement.flushEdge).cgPath(in: frames.shape)
        var checked = 0
        for x in stride(from: 2.0, to: frames.window.width, by: 17) {
            for y in stride(from: 2.0, to: frames.window.height, by: 17) {
                let p = CGPoint(x: x, y: y)
                guard !path.contains(p) else { continue }
                checked += 1
                #expect(NotchInteraction.state(pointInWindow: p, layout: layout,
                                               frames: frames, ringCount: 3) == .away)
            }
        }
        #expect(checked > 0)   // a sweep that checked nothing proves nothing
    }
}

@Test func pointerOnThePanel_isInteractiveAndKnowsItsRing() {
    let (layout, frames) = setup(.leftEdge)
    let second = layout.ringCentre(index: 1, in: frames.shape, expanded: false)
    #expect(NotchInteraction.state(pointInWindow: second, layout: layout, frames: frames,
                                   ringCount: 3) == .onPanel(ringIndex: 1))
}

@Test func pointerOnThePopover_keepsThePanelAlive() {
    let layout = NotchGeometry.layout(for: plain, placement: .leftEdge, ringCount: 3)
    let frames = NotchGeometry.frames(layout: layout, expanded: true, ringCount: 3,
                                      popover: (index: 0, windowCount: 3))
    let inside = CGPoint(x: frames.popover!.midX, y: frames.popover!.midY)
    #expect(NotchInteraction.state(pointInWindow: inside, layout: layout, frames: frames,
                                   ringCount: 3) == .onPopover)
    // Including the gap crossed on the way there, or it closes under the pointer mid-travel.
    let gap = CGPoint(x: frames.shape.maxX + NotchMetrics.popoverGap / 2,
                      y: frames.popover!.midY)
    #expect(NotchInteraction.state(pointInWindow: gap, layout: layout, frames: frames,
                                   ringCount: 3).isInteractive)
}

@Test func noPointer_isNotInteractive() {
    let (layout, frames) = setup(.topCenter)
    #expect(NotchInteraction.state(pointInWindow: nil, layout: layout, frames: frames,
                                   ringCount: 3) == .away)
}

// The other reported bug: a window manager (Magnet) tiling the panel into a window slot.
// `isMovable = false` only stops the user dragging it — the Accessibility API sets the
// position regardless, so the panel has to put itself back.
@Test func aMovedPanel_isDetectedAndRestored() {
    let expected = CGRect(x: 0, y: 500, width: 300, height: 400)
    #expect(NotchWindowGuard.needsRestore(current: expected, expected: expected) == false)
    #expect(NotchWindowGuard.needsRestore(current: expected.offsetBy(dx: 640, dy: 0),
                                          expected: expected))
    // Resized, not just moved — tiling does both.
    #expect(NotchWindowGuard.needsRestore(current: CGRect(x: 0, y: 500, width: 960, height: 1080),
                                          expected: expected))
}

@Test func subPixelDrift_isNotTreatedAsAMove() {
    // Backing-scale rounding must not start a restore/notify loop with the window server.
    let expected = CGRect(x: 0, y: 500, width: 300, height: 400)
    #expect(NotchWindowGuard.needsRestore(current: expected.offsetBy(dx: 0.25, dy: -0.25),
                                          expected: expected) == false)
}

// MARK: Reaching the popover across the gap (reported 2026-08-31)

// The bug: moving from a ring towards its popover crosses the panel's own padding, where no
// ring is under the pointer. Treating that as "no ring selected" closed the popover while the
// pointer was still ON the panel — and one step later, with no popover left to be inside of,
// the gap read as `.away` and the whole panel collapsed. The popover was unreachable.
@Test func leavingARingWithoutLeavingThePanel_keepsThePopoverOpen() {
    let d = NotchInteraction.decide(state: .onPanel(ringIndex: nil), current: 1,
                                    expandOnHover: true, showPopover: true)
    #expect(d.popoverIndex == 1)
    #expect(d.expanded)
}

@Test func crossingTheGapOntoThePopover_keepsIt() {
    let d = NotchInteraction.decide(state: .onPopover, current: 2,
                                    expandOnHover: true, showPopover: true)
    #expect(d.popoverIndex == 2)
    #expect(d.expanded)
    #expect(d.acceptsMouse)
}

@Test func movingOntoAnotherRing_switchesThePopover() {
    let d = NotchInteraction.decide(state: .onPanel(ringIndex: 3), current: 1,
                                    expandOnHover: true, showPopover: true)
    #expect(d.popoverIndex == 3)
}

@Test func leavingEverything_closesIt() {
    let d = NotchInteraction.decide(state: .away, current: 1,
                                    expandOnHover: true, showPopover: true)
    #expect(d.popoverIndex == nil)
    #expect(d.expanded == false)
    // And the window goes back to letting clicks through.
    #expect(d.acceptsMouse == false)
}

@Test func hoverExpansionOff_meansTheresNothingToReach() {
    let d = NotchInteraction.decide(state: .onPanel(ringIndex: 0), current: nil,
                                    expandOnHover: false, showPopover: true)
    #expect(d.expanded == false)
    #expect(d.popoverIndex == nil)
    // Still clickable where it is drawn — it is a panel, not a picture.
    #expect(d.acceptsMouse)
}

@Test func popoversOff_expandsWithoutOpeningOne() {
    let d = NotchInteraction.decide(state: .onPanel(ringIndex: 0), current: nil,
                                    expandOnHover: true, showPopover: false)
    #expect(d.expanded)
    #expect(d.popoverIndex == nil)
}

@Test func aStalePopoverIndexIsNotCarriedOntoAPanelThatHasNoRings() {
    // Accounts can be removed or hidden while the popover is open.
    let d = NotchInteraction.decide(state: .onPanel(ringIndex: nil), current: 4,
                                    expandOnHover: true, showPopover: true, ringCount: 2)
    #expect(d.popoverIndex == nil)
}
