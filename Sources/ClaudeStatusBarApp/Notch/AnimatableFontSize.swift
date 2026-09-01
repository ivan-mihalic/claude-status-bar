// Sources/ClaudeStatusBarApp/Notch/AnimatableFontSize.swift
import SwiftUI

/// Animates a font size.
///
/// SwiftUI cannot do this on its own: `Font` carries no animatable data, so a glyph whose
/// `.font(.system(size:))` follows a changing dimension **snaps** to its new size while
/// everything measured in points around it — frames, padding, `trim`, `StrokeStyle` — is
/// interpolated frame by frame. In the notch panel that showed up as the letters in the middle
/// of the rings arriving on a different schedule from the arcs around them.
///
/// The alternative, drawing at one size and using `scaleEffect`, animates just as smoothly but
/// scales rendered text: the glyph goes soft at every size except the reference one. This
/// re-typesets on each frame instead, which for a handful of single characters costs nothing
/// and stays crisp all the way through.
public struct AnimatableFontSize: ViewModifier, Animatable {
    public var size: CGFloat
    public var weight: Font.Weight
    public var design: Font.Design

    public init(size: CGFloat, weight: Font.Weight = .regular,
                design: Font.Design = .default) {
        self.size = size; self.weight = weight; self.design = design
    }

    public var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    public func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

public extension View {
    /// `.font(.system(size:weight:design:))`, but the size is animatable.
    func animatableFont(size: CGFloat, weight: Font.Weight = .regular,
                        design: Font.Design = .default) -> some View {
        modifier(AnimatableFontSize(size: size, weight: weight, design: design))
    }
}
