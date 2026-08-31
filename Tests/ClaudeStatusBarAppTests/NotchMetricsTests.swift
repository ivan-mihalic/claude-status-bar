import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

@Test func expandedPanel_alwaysCoversItsCollapsedSelf() {
    // The expanded panel must never be smaller than the pill it grew out of, or the
    // collapsed shape would poke out from under it.
    for placement in NotchPlacement.allCases {
        let collapsed = placement.isEdge ? NotchMetrics.syntheticEdgeSize : NotchMetrics.syntheticTopSize
        for count in 0...NotchMetrics.maxRings {
            let e = NotchMetrics.expandedSize(placement: placement, collapsed: collapsed,
                                              ringCount: count)
            #expect(e.width >= collapsed.width)
            #expect(e.height >= collapsed.height)
        }
    }
}

@Test func window_fitsThePanelAndItsTallestPopover() {
    // The window is fixed while the panel and popover change inside it; if it were too
    // small the popover would be clipped, and clipping looks like a rendering bug.
    for placement in NotchPlacement.allCases {
        let collapsed = placement.isEdge ? NotchMetrics.syntheticEdgeSize : NotchMetrics.syntheticTopSize
        let panel = NotchMetrics.expandedSize(placement: placement, collapsed: collapsed,
                                              ringCount: NotchMetrics.maxRings)
        let win = NotchMetrics.windowSize(placement: placement, collapsed: collapsed,
                                          ringCount: NotchMetrics.maxRings)
        #expect(win.width >= panel.width)
        #expect(win.height >= panel.height)
        #expect(win.width >= NotchMetrics.popoverWidth)
        #expect(win.height >= NotchMetrics.maxPopoverHeight)
    }
}

@Test func popoverHeight_growsWithTheNumberOfWindows() {
    #expect(NotchMetrics.popoverHeight(windowCount: 4) > NotchMetrics.popoverHeight(windowCount: 2))
    // No windows still needs room for the "no data" line.
    #expect(NotchMetrics.popoverHeight(windowCount: 0) == NotchMetrics.popoverHeight(windowCount: 1))
    #expect(NotchMetrics.maxPopoverHeight == NotchMetrics.popoverHeight(windowCount: 4))
}
