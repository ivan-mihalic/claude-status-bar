// Sources/ClaudeStatusBarApp/Accounts/OAuthLoginService.swift
import Foundation
import ClaudeStatusBarCore

public struct PendingLogin: Sendable {
    public let pkce: PKCE
    public let state: String
    public let authorizeURL: URL
}

public struct OAuthLoginService {
    private let oauth: OAuthClient
    private let endpoints: OAuthEndpoints
    private let config: OAuthConfig
    private let tokenStore: TokenStore
    private let opener: BrowserOpener

    public init(oauth: OAuthClient, endpoints: OAuthEndpoints, config: OAuthConfig,
                tokenStore: TokenStore, opener: BrowserOpener) {
        self.oauth = oauth; self.endpoints = endpoints; self.config = config
        self.tokenStore = tokenStore; self.opener = opener
    }

    public func begin() -> PendingLogin {
        let pkce = PKCE.generate()
        let state = PKCE.generate().verifier          // reuse CSPRNG for an opaque state
        let url = endpoints.authorizeURL(config: config, pkce: pkce, state: state)
        opener.open(url)
        return PendingLogin(pkce: pkce, state: state, authorizeURL: url)
    }

    public func complete(_ pending: PendingLogin, code rawCode: String,
                         accountID: UUID) async throws -> TokenBundle {
        // Anthropic's callback page shows "<code>#<state>" or "<code>&state=<state>";
        // accept a pasted value that may include either separator.
        let code = rawCode
            .split(whereSeparator: { $0 == "#" || $0 == "&" }).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawCode
        let bundle = try await oauth.exchange(code: code, verifier: pending.pkce.verifier,
                                              state: pending.state)
        try tokenStore.save(bundle, for: accountID)
        return bundle
    }
}
