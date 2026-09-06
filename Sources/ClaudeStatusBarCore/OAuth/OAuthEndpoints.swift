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

    public static let openAI = OAuthEndpoints(
        authorizeBase: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenHosts: [URL(string: "https://auth.openai.com/oauth/token")!]
    )

    public func authorizeURL(config: OAuthConfig, pkce: PKCE, state: String) -> URL {
        var comps = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        items.append(contentsOf: config.authorizeParameters.sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) })
        comps.queryItems = items
        return comps.url!
    }
}
