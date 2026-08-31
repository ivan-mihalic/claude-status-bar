// Sources/ClaudeStatusBarApp/Notch/NotchShape.swift
import SwiftUI
import CoreGraphics

/// The panel silhouette: one edge flush with the screen (square, full width — it touches the
/// bezel), the opposite corners rounded. Which edge is flush follows the placement, so the
/// same shape serves the notch and both screen sides.
public struct NotchShape: Shape, Equatable, Sendable {
    public enum FlushEdge: Equatable, Sendable { case top, leading, trailing }

    public let flushEdge: FlushEdge
    public let cornerRadius: CGFloat

    public init(flushEdge: FlushEdge = .top, cornerRadius: CGFloat = 20) {
        self.flushEdge = flushEdge; self.cornerRadius = cornerRadius
    }

    /// Built bottom-left-origin (CoreGraphics), matching `NotchGeometry`'s rects, so
    /// hit-testing and drawing agree.
    public func cgPath(in rect: CGRect) -> CGPath {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let p = CGMutablePath()
        guard r > 0 else { p.addRect(rect); return p }

        // Corner rounding is applied to the two corners away from the flush edge; the flush
        // edge itself stays square so no wallpaper shows between panel and bezel.
        switch flushEdge {
        case .top:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY), radius: r)
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.minY + r), radius: r)
        case .leading:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - r), radius: r)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY), radius: r)
        case .trailing:
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
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
