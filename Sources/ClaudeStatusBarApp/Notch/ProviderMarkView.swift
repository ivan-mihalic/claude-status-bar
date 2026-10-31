// Sources/ClaudeStatusBarApp/Notch/ProviderMarkView.swift
import SwiftUI
import ClaudeStatusBarCore

/// The little mark on a ring's shoulder saying which service the numbers come from.
///
/// These are drawn, not bundled. Shipping a company's actual logo file inside a public repo
/// is a trademark question rather than a technical one, so each mark here is a simple,
/// recognisable geometric stand-in: a burst, a chat glyph, a cube. If real artwork is ever
/// licensed, only this view changes — everything else asks for a `Provider`.
public struct ProviderMarkView: View {
    let provider: Provider
    let diameter: CGFloat

    public init(provider: Provider, diameter: CGFloat = 16) {
        self.provider = provider; self.diameter = diameter
    }

    private var tint: Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.42, blue: 0.24)   // warm ochre
        case .codex:  return Color(white: 0.92)
        case .cursor: return Color(red: 0.55, green: 0.62, blue: 0.95)
        }
    }

    public var body: some View {
        ZStack {
            Circle().fill(.black)
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            mark.frame(width: diameter * 0.62, height: diameter * 0.62)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)   // the ring already announces the account
    }

    @ViewBuilder private var mark: some View {
        switch provider {
        case .claude: Burst(spokes: 8).stroke(tint, lineWidth: max(diameter * 0.07, 1))
        case .codex:  CodexKnot(tint: tint, lineWidth: max(diameter * 0.065, 0.8))
        case .cursor: Cube().stroke(tint, style: StrokeStyle(lineWidth: max(diameter * 0.07, 1),
                                                             lineJoin: .round))
        }
    }
}

/// A compact six-lobed knot inspired by the Codex/OpenAI mark. It stays legible at the
/// 11-point size used on a collapsed ring, where a plain outline circle did not identify it.
private struct CodexKnot: View {
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .stroke(tint, lineWidth: lineWidth)
                        .frame(width: size * 0.38, height: size * 0.72)
                        .offset(y: -size * 0.10)
                        .rotationEffect(.degrees(Double(index) * 60))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// A radial burst: spokes from the centre, evenly spaced.
struct Burst: Shape {
    let spokes: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<max(spokes, 1) {
            let a = Double(i) / Double(max(spokes, 1)) * 2 * .pi
            path.move(to: CGPoint(x: c.x + cos(a) * r * 0.28, y: c.y + sin(a) * r * 0.28))
            path.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        return path
    }
}

/// An isometric cube outline.
struct Cube: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let top = CGPoint(x: rect.minX + w / 2, y: rect.minY)
        let left = CGPoint(x: rect.minX, y: rect.minY + h * 0.27)
        let right = CGPoint(x: rect.maxX, y: rect.minY + h * 0.27)
        let bottom = CGPoint(x: rect.minX + w / 2, y: rect.maxY)
        let midLeft = CGPoint(x: rect.minX, y: rect.minY + h * 0.73)
        let midRight = CGPoint(x: rect.maxX, y: rect.minY + h * 0.73)
        let centre = CGPoint(x: rect.minX + w / 2, y: rect.minY + h * 0.5)
        path.move(to: top); path.addLine(to: right); path.addLine(to: midRight)
        path.addLine(to: bottom); path.addLine(to: midLeft); path.addLine(to: left)
        path.closeSubpath()
        path.move(to: top); path.addLine(to: centre)
        path.move(to: centre); path.addLine(to: midLeft)
        path.move(to: centre); path.addLine(to: midRight)
        return path
    }
}
