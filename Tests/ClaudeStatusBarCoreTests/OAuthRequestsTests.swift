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

@Test func codexAuthorizeURL_matchesTheBrowserFlow() throws {
    let url = OAuthEndpoints.openAI.authorizeURL(
        config: .codex, pkce: PKCE(verifier: "v", challenge: "challenge"), state: "state")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    #expect(query["id_token_add_organizations"] == "true")
    #expect(query["codex_cli_simplified_flow"] == "true")
    #expect(query["originator"] == "codex_cli_rs")
    #expect(query["scope"]?.contains("offline_access") == true)
    #expect(query["scope"]?.contains("api.connectors.read") == true)
}

@Test func exchangeRequest_isFormURLEncodedPOST() throws {
    let req = OAuthRequests.exchange(
        tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        config: .claudeCode, code: "CODE", verifier: "VER", state: "ST")
    #expect(req.httpMethod == "POST")
    #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let bodyData = try #require(req.httpBody)
    let body = try #require(String(data: bodyData, encoding: .utf8))
    #expect(body.contains("grant_type=authorization_code"))
    #expect(body.contains("code=CODE"))
    #expect(body.contains("code_verifier=VER"))
    #expect(body.contains("state=ST"))
    #expect(body.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
}

@Test func refreshRequest_hasGrantTypeRefresh() throws {
    let req = OAuthRequests.refresh(
        tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        config: .claudeCode, refreshToken: "RT")
    let bodyData = try #require(req.httpBody)
    let body = try #require(String(data: bodyData, encoding: .utf8))
    #expect(body.contains("grant_type=refresh_token"))
    #expect(body.contains("refresh_token=RT"))
    #expect(body.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
}
