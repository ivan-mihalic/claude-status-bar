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
}
