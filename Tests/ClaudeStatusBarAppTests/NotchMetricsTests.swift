import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

@Test func expandedHeight_growsWithRingsAndNeverShrinksBelowTheNotch() {
    let one = NotchMetrics.expandedHeight(collapsedHeight: 32, ringCount: 1)
    let three = NotchMetrics.expandedHeight(collapsedHeight: 32, ringCount: 3)
    #expect(three > one)
    #expect(one > 32)
    // Zero accounts still needs room for the "No accounts" line and the gear.
    #expect(NotchMetrics.expandedHeight(collapsedHeight: 32, ringCount: 0) == one)
}

@Test func expandedHeight_staysInsideTheWindow() {
    // The window is fixed; the drawn panel must never exceed it or it gets clipped.
    let tallest = NotchMetrics.expandedHeight(collapsedHeight: 38, ringCount: 99)
    #expect(tallest <= NotchMetrics.panelSize.height)
    #expect(NotchMetrics.expandedWidth <= NotchMetrics.panelSize.width)
}
