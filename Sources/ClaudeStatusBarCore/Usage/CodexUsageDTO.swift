// Sources/ClaudeStatusBarCore/Usage/CodexUsageDTO.swift
import Foundation

/// The shape of `GET https://chatgpt.com/backend-api/wham/usage`.
///
/// Measured against a live Plus account on 2026-08-31, not inferred: the field names below
/// come from an actual 200 response, and the fixture in the tests is that response with its
/// identifiers redacted. Everything optional is optional because the live payload really did
/// send `null` for it.
public struct CodexUsageDTO: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let usedPercent: Double
        public let limitWindowSeconds: Int
        public let resetAfterSeconds: Int?
        /// Unix epoch seconds. Preferred over `resetAfterSeconds` — an absolute moment
        /// survives a laptop sleeping through the window.
        public let resetAt: Double?

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
    }

    public struct RateLimit: Decodable, Sendable {
        public let primaryWindow: Window?
        public let secondaryWindow: Window?

        private enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    public let planType: String?
    public let rateLimit: RateLimit?

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }
}

public enum CodexUsageAdapter {
    /// Codex can report one or two windows and names them only by position, so the labels
    /// come from their length: 18 000 s is the 5-hour session, 604 800 s the week. Anything
    /// else is labelled by its own duration rather than guessed at.
    public static func label(forWindowSeconds seconds: Int) -> String {
        switch seconds {
        case 18_000:  return "Session"
        case 604_800: return "Week"
        default:
            let hours = max(seconds / 3600, 1)
            return hours >= 48 ? "\(hours / 24)-day window" : "\(hours)-hour window"
        }
    }

    public static func key(forWindowSeconds seconds: Int) -> String {
        switch seconds {
        case 18_000:  return "five_hour"
        case 604_800: return "seven_day"
        default:      return "window_\(seconds)"
        }
    }

    public static func normalize(_ dto: CodexUsageDTO, fetchedAt: Date) throws -> UsageSnapshot {
        let available = [dto.rateLimit?.primaryWindow, dto.rateLimit?.secondaryWindow]
            .compactMap { $0 }
        guard !available.isEmpty else {
            throw UsageAdapterError.missingCoreWindows
        }
        let normalized = available.map { window($0, now: fetchedAt) }
        let session = normalized.first { $0.key == "five_hour" }
        let week = normalized.first { $0.key == "seven_day" }
        let other = normalized.filter { $0.key != "five_hour" && $0.key != "seven_day" }
        return UsageSnapshot(session: session,
                             weekAll: week,
                             weekPremium: other,
                             fetchedAt: fetchedAt)
    }

    private static func window(_ w: CodexUsageDTO.Window, now: Date) -> UsageWindow {
        // Absolute first: `reset_after_seconds` is measured from when the server answered,
        // so a snapshot that sat through a sleep would count down from the wrong moment.
        let resets = w.resetAt.map { Date(timeIntervalSince1970: $0) }
            ?? now.addingTimeInterval(TimeInterval(w.resetAfterSeconds ?? w.limitWindowSeconds))
        return UsageWindow(key: key(forWindowSeconds: w.limitWindowSeconds),
                           label: label(forWindowSeconds: w.limitWindowSeconds),
                           utilization: min(max(w.usedPercent, 0), 100),
                           resetsAt: resets)
    }
}
