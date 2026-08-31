// Sources/ClaudeStatusBarCore/Model/Provider.swift
import Foundation

/// The service an account belongs to.
///
/// Only `claude` can actually be signed in today — the app speaks one usage API. The type
/// exists now so the notch can badge a ring with where its numbers come from, and so adding
/// a second service later is a new case rather than a reshuffle of every view.
public enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        case .cursor: return "Cursor"
        }
    }

    /// Whether the app can sign in to this service. Everything but Claude is a placeholder
    /// for a provider whose personal-plan limits we have not established an endpoint for.
    public var isSupported: Bool { self == .claude }
}
