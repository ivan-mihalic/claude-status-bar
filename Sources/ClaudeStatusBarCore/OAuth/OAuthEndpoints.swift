// Sources/ClaudeStatusBarCore/OAuth/OAuthEndpoints.swift
import Foundation

public struct OAuthEndpoints: Sendable {
    public let authorizeBase: URL
    public let tokenHosts: [URL]   // tried in order (domain caveat)

    public init(authorizeBase: URL, tokenHosts: [URL]) {
        self.authorizeBase = authorizeBase; self.tokenHosts = tokenHosts
    }

    public static let production = OAuthEndpoints(
        authorizeBase: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenHosts: [
            URL(string: "https://platform.claude.com/v1/oauth/token")!,
            URL(string: "https://console.anthropic.com/v1/oauth/token")!,
        ]
    )

    public func authorizeURL(config: OAuthConfig, pkce: PKCE, state: String) -> URL {
        var comps = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return comps.url!
    }
}
