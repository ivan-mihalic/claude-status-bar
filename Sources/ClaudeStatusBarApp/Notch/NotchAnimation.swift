// Sources/ClaudeStatusBarApp/Notch/NotchAnimation.swift
import SwiftUI

/// Timing for the panel's two moving parts.
///
/// They are staged, not simultaneous, and the order flips with direction:
///
/// - **Opening** — the panel grows first and the rings catch up. The container has to arrive
///   before its contents, or the gear appears floating over a notch that has not finished
///   expanding yet.
/// - **Closing** — the rings leave first and the panel follows. Content that lingers while
///   the shape shrinks gets clipped by its own container on the way out.
///
/// The numbers live here rather than inline so the *ordering* can be asserted; it is the kind
/// of intent that gets undone by someone nudging one value in isolation.
public enum NotchAnimation {
    /// Time to settle, in seconds — a spring's `response`.
    public static let containerOpen: Double = 0.24
    public static let containerClose: Double = 0.30
    public static let contentOpen: Double = 0.26
    public static let contentClose: Double = 0.11

    /// The content waits this long before starting to appear.
    public static let contentOpenDelay: Double = 0.07
    /// Closing has no delay on either part: the content simply moves faster.
    public static let contentCloseDelay: Double = 0

    /// Extra wait before treating a spring as finished.
    ///
    /// `response` is a spring's natural period, not the moment it stops moving — at exactly
    /// `containerClose` the shape is still a little wider than it will end up. Anything that
    /// resizes the window to fit the finished shape has to allow for that, or it clips the
    /// tail of the animation.
    public static let settleMargin: Double = 0.15

    /// When each part has finished, measured from the start of the gesture.
    public static func finish(container: Bool, expanding: Bool) -> Double {
        if container { return expanding ? containerOpen : containerClose }
        return expanding ? contentOpen + contentOpenDelay : contentClose + contentCloseDelay
    }

    /// Whether the rings should be laid out at their open size even while invisible.
    ///
    /// A panel that hides its rings at rest keeps them mounted at full size and only fades
    /// them: if they were mounted small and grew, the fade would come with a resize, which is
    /// the "flying in" look again. A panel that *shows* rings at rest has to follow the real
    /// state, because there the size change is the animation.
    public static func ringsUseOpenSize(showsRingsAtRest: Bool, expanded: Bool) -> Bool {
        showsRingsAtRest ? expanded : true
    }

    public static func container(expanded: Bool) -> Animation {
        expanded ? .spring(response: containerOpen, dampingFraction: 0.84)
                 : .spring(response: containerClose, dampingFraction: 0.88)
    }

    public static func content(expanded: Bool) -> Animation {
        expanded ? .spring(response: contentOpen, dampingFraction: 0.86).delay(contentOpenDelay)
                 : .easeIn(duration: contentClose)
    }
}
