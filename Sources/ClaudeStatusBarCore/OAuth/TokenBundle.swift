// Sources/ClaudeStatusBarCore/OAuth/TokenBundle.swift
import Foundation

public struct TokenBundle: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scopes: [String]

    public init(accessToken: String, refreshToken: String,
                expiresAt: Date, scopes: [String]) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.scopes = scopes
    }

    public func isExpiring(within seconds: TimeInterval, now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) <= seconds
    }
}

public struct TokenResponse: Decodable, Sendable {
    public let access_token: String
    public let refresh_token: String?
    public let expires_in: Double?
    public let scope: String?

    /// RFC 6749 §5.1: `refresh_token` may be omitted (keep the old one);
    /// `expires_in` is optional (default to a conservative 1h).
    public func bundle(now: Date, previousRefreshToken: String) -> TokenBundle {
        TokenBundle(
            accessToken: access_token,
            refreshToken: refresh_token ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(expires_in ?? 3600),
            scopes: (scope ?? "").split(separator: " ").map(String.init)
        )
    }
}
