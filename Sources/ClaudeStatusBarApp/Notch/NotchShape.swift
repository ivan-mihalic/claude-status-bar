// Sources/ClaudeStatusBarApp/Notch/NotchShape.swift
import SwiftUI
import CoreGraphics

/// The panel silhouette: square, full-width top edge (it is flush with the screen edge),
/// rounded bottom corners. Paired with `InverseCorner`, which fills the wedge between the
/// panel's straight side and the screen edge — the detail that makes it read as an extension
/// of the notch instead of a floating rectangle.
public struct NotchShape: Shape, Equatable, Sendable {
    public let topRadius: CGFloat
    public let bottomRadius: CGFloat

    public init(topRadius: CGFloat = 8, bottomRadius: CGFloat = 20) {
        self.topRadius = topRadius; self.bottomRadius = bottomRadius
    }

    /// Note the coordinate space: this `CGPath` is built bottom-left-origin (CoreGraphics),
    /// matching `NotchGeometry`'s rects, so hit-testing and drawing agree.
    public func cgPath(in rect: CGRect) -> CGPath {
        let b = min(bottomRadius, min(rect.width, rect.height) / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + b))
        if b > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX - b, y: rect.minY), radius: b)
        }
        p.addLine(to: CGPoint(x: rect.minX + b, y: rect.minY))
        if b > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.minY + b), radius: b)
        }
        p.closeSubpath()
        return p
    }

    public func path(in rect: CGRect) -> Path {
        // SwiftUI's y axis points down; flip so the shape reads the same either way.
        var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -rect.height)
        let cg = cgPath(in: CGRect(origin: .zero, size: rect.size))
        return Path(cg.copy(using: &flip) ?? cg).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The inverse corner drawn *outside* the panel body, filling the wedge between the panel's
/// straight side and the screen edge. Two of these, mirrored, sit beside the panel's bottom
/// corners; keeping them separate means the panel body stays a simple, hit-testable shape.
public struct InverseCorner: Shape {
    public let radius: CGFloat
    public let flipped: Bool

    public init(radius: CGFloat = 12, flipped: Bool = false) {
        self.radius = radius; self.flipped = flipped
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return flipped ? path.applying(CGAffineTransform(scaleX: -1, y: 1)
            .translatedBy(x: -rect.width, y: 0)) : path
    }
}
