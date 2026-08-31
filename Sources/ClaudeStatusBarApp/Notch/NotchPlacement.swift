// Sources/ClaudeStatusBarApp/Notch/NotchPlacement.swift
import CoreGraphics

/// Where the panel lives. `topCenter` is the notch proper; the edge placements park it
/// against the side of the screen at a user-chosen height, for Macs whose notch is busy
/// (or absent) and for people who want it out of the menu bar's way.
public enum NotchPlacement: String, CaseIterable, Codable, Sendable, Identifiable {
    case topCenter, leftEdge, rightEdge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .topCenter: return "Top (notch)"
        case .leftEdge:  return "Left edge"
        case .rightEdge: return "Right edge"
        }
    }

    public var isEdge: Bool { self != .topCenter }

    /// Rings run across the short axis of the panel: a row under the notch, a column
    /// down an edge.
    public var ringsAreVertical: Bool { isEdge }

    /// Which side of the panel the shape is flush with — the side that has no rounding
    /// because it touches the screen edge.
    public var flushEdge: NotchShape.FlushEdge {
        switch self {
        case .topCenter: return .top
        case .leftEdge:  return .leading
        case .rightEdge: return .trailing
        }
    }

    /// Where the detail popover sits relative to the panel.
    public var popoverSide: PopoverSide {
        switch self {
        case .topCenter: return .below
        case .leftEdge:  return .trailing
        case .rightEdge: return .leading
        }
    }
}

public enum PopoverSide: Equatable, Sendable { case below, leading, trailing }
