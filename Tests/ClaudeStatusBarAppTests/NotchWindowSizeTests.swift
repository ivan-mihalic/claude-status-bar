// Tests/ClaudeStatusBarAppTests/NotchWindowSizeTests.swift
import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

private let plain = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                  topInset: 0, auxiliaryTopLeftWidth: nil)
private let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                    topInset: 38, auxiliaryTopLeftWidth: 620)

/// Where the drawn panel actually lands on screen, given a window frame and the size of the
/// window it is drawn into. The whole point of the resting window is that this answer does
/// not change when the window grows.
private func shapeOnScreen(_ layout: NotchLayout, windowFrame: CGRect,
                           windowSize: CGSize, size: CGSize) -> CGRect {
    let local = layout.shapeRect(windowSize: windowSize, size: size)
    return local.offsetBy(dx: windowFrame.minX, dy: windowFrame.minY)
}

// Dokud panel jen leží, je okno přesně tak velké jako on — jinak kolem něj zůstane
// průhledný okraj, který polyká kliknutí, a jediná obrana proti tomu je sledovat
// myš globálně přes celou obrazovku.
@Test func restingWindow_isExactlyTheDrawnPanel() {
    for placement in NotchPlacement.allCases {
        for rings in [0, 1, 3, 6] {
            let layout = NotchGeometry.layout(for: plain, placement: placement,
                                              ringCount: rings, showRingsAtRest: true)
            let windowSize = NotchMetrics.windowSize(
                placement: placement, collapsed: layout.collapsed.size,
                ringCount: rings, notchClearance: layout.notchClearance)
            let frame = NotchGeometry.collapsedWindowFrame(
                layout: layout, expandedFrame: layout.panelFrame(expandedSize: windowSize),
                windowSize: windowSize)
            #expect(frame.size == layout.collapsed.size)
        }
    }
}

// Tohle je ta vlastnost, kvůli které se okno vůbec smí zvětšovat: rozbalení nesmí
// panelem pohnout ani o pixel, jinak to vypadá jako lupnutí.
@Test func growingTheWindow_doesNotMoveTheDrawnPanel() {
    for metrics in [plain, notched] {
        for placement in NotchPlacement.allCases {
            for percent in [0.0, 22.0, 50.0, 100.0] {
                for rings in [0, 2, 6] {
                    let layout = NotchGeometry.layout(
                        for: metrics, placement: placement, edgeOffsetPercent: percent,
                        ringCount: rings, showRingsAtRest: true)
                    let windowSize = NotchMetrics.windowSize(
                        placement: placement, collapsed: layout.collapsed.size,
                        ringCount: rings, notchClearance: layout.notchClearance)
                    let expandedFrame = layout.panelFrame(expandedSize: windowSize)
                    let collapsedFrame = NotchGeometry.collapsedWindowFrame(
                        layout: layout, expandedFrame: expandedFrame, windowSize: windowSize)

                    let inSmall = shapeOnScreen(layout, windowFrame: collapsedFrame,
                                                windowSize: layout.collapsed.size,
                                                size: layout.collapsed.size)
                    let inBig = shapeOnScreen(layout, windowFrame: expandedFrame,
                                              windowSize: windowSize,
                                              size: layout.collapsed.size)
                    #expect(inSmall == inBig,
                            "\(placement) \(percent)% \(rings) prstenců: \(inSmall) != \(inBig)")
                }
            }
        }
    }
}

// Rámečky se počítají ze skutečné velikosti okna, ne z té největší možné — jinak by
// se v malém okně kreslil panel mimo něj.
@Test func frames_honourTheWindowTheyAreDrawnInto() {
    let layout = NotchGeometry.layout(for: plain, placement: .rightEdge, ringCount: 3)
    let small = NotchGeometry.frames(layout: layout, expanded: false, ringCount: 3,
                                     popover: nil, windowSize: layout.collapsed.size)
    #expect(small.window == layout.collapsed.size)
    #expect(small.shape == CGRect(origin: .zero, size: layout.collapsed.size))

    // Bez parametru zůstává původní chování: okno velké na rozbalený panel i popover.
    let big = NotchGeometry.frames(layout: layout, expanded: false, ringCount: 3, popover: nil)
    #expect(big.window.width > small.window.width)
    #expect(big.shape.size == small.shape.size)
}
