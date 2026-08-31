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
