// Tests/ClaudeStatusBarCoreTests/OAuthRequestsTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test func authorizeURL_hasRequiredParams() throws {
    let pkce = PKCE(verifier: "v", challenge: "chal")
    let url = OAuthEndpoints.production.authorizeURL(
        config: .claudeCode, pkce: pkce, state: "st8"
    )
    let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = try #require(comps.queryItems)
    let q = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
    #expect(comps.host == "claude.ai")
    #expect(comps.path == "/oauth/authorize")
    #expect(q["response_type"] == "code")
    #expect(q["client_id"] == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
    #expect(q["code_challenge"] == "chal")
    #expect(q["code_challenge_method"] == "S256")
    #expect(q["state"] == "st8")
    #expect(q["redirect_uri"] == "https://console.anthropic.com/oauth/code/callback")
    let scope = try #require(q["scope"])
    #expect(scope.contains("user:profile"))
}
