// Sources/ClaudeStatusBarCore/OAuth/TokenBundle.swift
import Foundation

public struct TokenBundle: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scopes: [String]
    /// ChatGPT workspace/account used to route Codex backend requests. Optional so token
    /// bundles saved before Codex support continue to decode.
    public var accountID: String?

    public init(accessToken: String, refreshToken: String,
                expiresAt: Date, scopes: [String], accountID: String? = nil) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.scopes = scopes
        self.accountID = accountID
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
    public let id_token: String?
    public let account_id: String?

    /// RFC 6749 §5.1: `refresh_token` may be omitted (keep the old one);
    /// `expires_in` is optional (default to a conservative 1h).
    public func bundle(now: Date, previousRefreshToken: String,
                       previousAccountID: String? = nil) -> TokenBundle {
        TokenBundle(
            accessToken: access_token,
            refreshToken: refresh_token ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(expires_in ?? 3600),
            scopes: (scope ?? "").split(separator: " ").map(String.init),
            accountID: account_id
                ?? id_token.flatMap(ChatGPTTokenClaims.accountID(from:))
                ?? ChatGPTTokenClaims.accountID(from: access_token)
                ?? previousAccountID
        )
    }
}

/// Reads the untrusted routing claim from a token already accepted as an OAuth bearer token.
/// This does not authenticate the JWT; the server still validates the signed token itself.
enum ChatGPTTokenClaims {
    static func accountID(from token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let data = Base64URL.decode(String(parts[1])),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = root["https://api.openai.com/auth"] as? [String: Any],
              let value = auth["chatgpt_account_id"] as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
