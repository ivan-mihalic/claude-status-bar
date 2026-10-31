// Sources/ClaudeStatusBarCore/Model/Provider.swift
import Foundation

/// The service an account belongs to.
///
/// Both Claude and Codex subscription accounts can be signed in independently.
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

    /// The providers actually offered when adding an account.
    public static var selectableCases: [Provider] { allCases.filter(\.isSupported) }

    /// Why an unsupported provider is greyed out, so the UI never refuses without saying.
    public var unsupportedReason: String? {
        switch self {
        case .claude: return nil
        case .codex: return nil
        case .cursor:
            return "Cursor has no usage API - its limits are only visible in the web dashboard."
        }
    }
}
