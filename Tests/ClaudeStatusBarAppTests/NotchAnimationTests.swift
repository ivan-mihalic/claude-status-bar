import Testing
@testable import ClaudeStatusBarApp

// The reported feel: opening, the gear showed up before the notch had finished growing;
// closing, the rings hung around inside a shrinking panel. Both are ordering problems, so
// the ordering is what gets asserted — not the individual numbers, which are free to change.

@Test func opening_thePanelArrivesBeforeItsContents() {
    #expect(NotchAnimation.finish(container: true, expanding: true)
            < NotchAnimation.finish(container: false, expanding: true))
}

@Test func closing_theContentsLeaveBeforeThePanel() {
    #expect(NotchAnimation.finish(container: false, expanding: false)
            < NotchAnimation.finish(container: true, expanding: false))
}

@Test func openingIsBriskerThanClosing() {
    // Growing should feel eager, shrinking should feel like it is settling back.
    #expect(NotchAnimation.containerOpen < NotchAnimation.containerClose)
}

@Test func contentLeadsOutFasterThanItComesIn() {
    #expect(NotchAnimation.contentClose < NotchAnimation.contentOpen)
    #expect(NotchAnimation.contentCloseDelay == 0)   // nothing waits on the way out
    #expect(NotchAnimation.contentOpenDelay > 0)
}

@Test func everyStageIsShortEnoughToFeelLikeHover_notLikeALoad() {
    for expanding in [true, false] {
        for container in [true, false] {
            #expect(NotchAnimation.finish(container: container, expanding: expanding) < 0.45)
        }
    }
}

// MARK: What is mounted when

// The bug: with rings hidden at rest, the stack was *inserted* into the view tree on expand.
// A view that appears already visible cannot fade — the rings popped in fully formed while
// the panel was still growing, which is the opposite of the intended order. Keeping them
// mounted and animating opacity is what makes the staging apply at all.
@Test func hiddenAtRest_meansMountedAtOpenSizeAndMerelyInvisible() {
    #expect(NotchAnimation.ringsUseOpenSize(showsRingsAtRest: false, expanded: false))
    #expect(NotchAnimation.ringsUseOpenSize(showsRingsAtRest: false, expanded: true))
}

@Test func shownAtRest_followsTheRealState_becauseThereTheResizeIsTheAnimation() {
    #expect(NotchAnimation.ringsUseOpenSize(showsRingsAtRest: true, expanded: true))
    #expect(NotchAnimation.ringsUseOpenSize(showsRingsAtRest: true, expanded: false) == false)
}
