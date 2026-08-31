import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

private let shapeRect = CGRect(x: 0, y: 0, width: 200, height: 100)
private let shape = NotchShape(topRadius: 8, bottomRadius: 20)

@Test func path_staysInsideItsRect() {
    #expect(shape.cgPath(in: shapeRect).boundingBox.width <= shapeRect.width)
    #expect(shape.cgPath(in: shapeRect).boundingBox.height <= shapeRect.height)
}

@Test func centre_isInsideAndBottomCornersAreRoundedAway() {
    let path = shape.cgPath(in: shapeRect)
    #expect(path.contains(CGPoint(x: 100, y: 50)))
    // Bottom corners are rounded, so the exact corner point is outside the fill.
    #expect(!path.contains(CGPoint(x: 0.5, y: 0.5)))
    #expect(!path.contains(CGPoint(x: 199.5, y: 0.5)))
}

@Test func topEdge_isFlush() {
    // The panel hangs off the top of the screen: the top edge must be square and full width,
    // otherwise a hardware notch shows a sliver of wallpaper beside it.
    let path = shape.cgPath(in: shapeRect)
    #expect(path.contains(CGPoint(x: 1, y: shapeRect.maxY - 1)))
    #expect(path.contains(CGPoint(x: shapeRect.maxX - 1, y: shapeRect.maxY - 1)))
}

@Test func zeroRadii_giveAPlainRectangle() {
    let square = NotchShape(topRadius: 0, bottomRadius: 0).cgPath(in: shapeRect)
    #expect(square.contains(CGPoint(x: 0.5, y: 0.5)))
}
