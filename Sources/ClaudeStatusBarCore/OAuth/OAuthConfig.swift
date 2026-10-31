// Sources/ClaudeStatusBarCore/OAuth/OAuthConfig.swift
import Foundation

public struct OAuthConfig: Equatable, Sendable {
    public let clientID: String
    public let scopes: [String]
    public let redirectURI: String
    public let authorizeParameters: [String: String]

    public init(clientID: String, scopes: [String], redirectURI: String,
                authorizeParameters: [String: String] = [:]) {
        self.clientID = clientID; self.scopes = scopes; self.redirectURI = redirectURI
        self.authorizeParameters = authorizeParameters
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
    /// Values kept in sync with the open-source Codex CLI login implementation.
    public static let codex = OAuthConfig(
        clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: ["openid", "profile", "email", "offline_access",
                 "api.connectors.read", "api.connectors.invoke"],
        redirectURI: "http://localhost:1455/auth/callback",
        authorizeParameters: [
            "id_token_add_organizations": "true",
            "codex_cli_simplified_flow": "true",
            "originator": "codex_cli_rs",
        ]
    )

    /// Google Antigravity's own desktop OAuth client. Google lets an installed-app client
    /// redirect to any loopback port, so the redirect below is the one the open-source
    /// Antigravity integrations use. `access_type=offline` + `prompt=consent` are what make
    /// Google issue a refresh token at all. Values verified on 2026-10-31 against
    /// opencode-antigravity-auth (src/constants.ts, src/antigravity/oauth.ts).
    ///
    /// Google's token endpoint also demands the client's `client_secret`. It is deliberately
    /// not in this repository: the user enters it when adding the account and it is kept
    /// with that account's tokens in the Keychain (`TokenBundle.clientSecret`).
    public static let antigravity = OAuthConfig(
        clientID: "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com",
        scopes: ["https://www.googleapis.com/auth/cloud-platform",
                 "https://www.googleapis.com/auth/userinfo.email",
                 "https://www.googleapis.com/auth/userinfo.profile",
                 "https://www.googleapis.com/auth/cclog",
                 "https://www.googleapis.com/auth/experimentsandconfigs"],
        redirectURI: "http://localhost:51121/oauth-callback",
        authorizeParameters: [
            "access_type": "offline",
            "prompt": "consent",
        ]
    )
}
