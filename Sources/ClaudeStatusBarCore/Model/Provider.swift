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

    /// Whether the app can sign in to this service.
    ///
    /// Cursor is listed but not supported on purpose: as of 2026-08-31 its CLI exposes no
    /// usage endpoint at all, and the numbers live only in the web dashboard behind a
    /// session cookie. Scraping that would break silently and then show stale figures,
    /// which is worse than not offering it.
    public var isSupported: Bool { self == .claude || self == .codex }

    /// Why an unsupported provider is greyed out, so the UI never refuses without saying.
    public var unsupportedReason: String? {
        switch self {
        case .claude, .codex: return nil
        case .cursor:
            return "Cursor has no usage API - its limits are only visible in the web dashboard."
        }
    }
}
