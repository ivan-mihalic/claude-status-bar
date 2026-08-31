// Sources/ClaudeStatusBarCore/OAuth/OAuthConfig.swift
import Foundation

public struct OAuthConfig: Equatable, Sendable {
    public let clientID: String
    public let scopes: [String]
    public let redirectURI: String

    public init(clientID: String, scopes: [String], redirectURI: String) {
        self.clientID = clientID; self.scopes = scopes; self.redirectURI = redirectURI
    }

    // Full browser login: user:profile is required for /api/oauth/usage.
    public static let claudeCode = OAuthConfig(
        clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scopes: ["org:create_api_key", "user:profile", "user:inference"],
        redirectURI: "https://console.anthropic.com/oauth/code/callback"
    )

    /// The Codex CLI's own OAuth client. Its redirect is a fixed loopback address that cannot
    /// be changed from here, which is why signing in to Codex needs a short-lived local
    /// listener (and the `network.server` entitlement) while the Anthropic flow does not.
    /// Values read out of the shipped `@openai/codex` binary on 2026-08-31.
    public static let codex = OAuthConfig(
        clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: ["openid", "profile", "email", "offline_access"],
        redirectURI: "http://localhost:1455/auth/callback"
    )
}
