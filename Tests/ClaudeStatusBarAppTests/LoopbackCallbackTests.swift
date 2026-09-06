import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private let path = "/auth/callback"

@Test func callback_readsTheCodeAndState() throws {
    let r = try #require(LoopbackCallbackServer.parse(
        requestLine: "GET /auth/callback?code=abc123&state=xyz HTTP/1.1", expectedPath: path))
    #expect(try r.get() == LoopbackCallbackServer.Callback(code: "abc123", state: "xyz"))
}

// The failure that matters: a denial carries no `code`, and reading it as "keep waiting"
// would hang the sign-in sheet until the timeout with no explanation.
@Test func aDeniedAuthorizationIsAFailure_notSilence() {
    let r = LoopbackCallbackServer.parse(
        requestLine: "GET /auth/callback?error=access_denied&error_description=User+said+no HTTP/1.1",
        expectedPath: path)
    guard case .failure(let f)? = r else { Issue.record("expected a failure"); return }
    #expect(f == .authorizationDenied("User said no"))
}

@Test func deniedWithoutADescription_stillReportsTheCode() {
    let r = LoopbackCallbackServer.parse(requestLine: "GET /auth/callback?error=server_error HTTP/1.1",
                                         expectedPath: path)
    guard case .failure(let f)? = r else { Issue.record("expected a failure"); return }
    #expect(f == .authorizationDenied("server_error"))
}

@Test func unrelatedRequestsAreIgnoredRatherThanMisread() {
    // Anything else that hits the port — a browser probing /favicon.ico, another app — must
    // not end the wait.
    #expect(LoopbackCallbackServer.parse(requestLine: "GET /favicon.ico HTTP/1.1",
                                         expectedPath: path) == nil)
    #expect(LoopbackCallbackServer.parse(requestLine: "POST /auth/callback?code=x HTTP/1.1",
                                         expectedPath: path) == nil)
    #expect(LoopbackCallbackServer.parse(requestLine: "GET /auth/callback HTTP/1.1",
                                         expectedPath: path) == nil)
    #expect(LoopbackCallbackServer.parse(requestLine: "", expectedPath: path) == nil)
    // An empty code is not a code.
    #expect(LoopbackCallbackServer.parse(requestLine: "GET /auth/callback?code= HTTP/1.1",
                                         expectedPath: path) == nil)
}

@Test func stateIsOptionalButReportedWhenSent() throws {
    let r = try #require(LoopbackCallbackServer.parse(
        requestLine: "GET /auth/callback?code=abc HTTP/1.1", expectedPath: path))
    #expect(try r.get().state == nil)
}

@Test func theListenerAddressComesFromTheRedirectURI() async {
    // The listener must never be configured by hand: a port that disagrees with the redirect
    // the provider was given would wait forever on the wrong socket.
    let server = LoopbackCallbackServer(redirectURI: OAuthConfig.codex.redirectURI)
    #expect(server != nil)
    // Anything that is not a loopback address is refused rather than quietly bound.
    #expect(LoopbackCallbackServer(redirectURI: "https://console.anthropic.com/oauth/code/callback") == nil)
    #expect(LoopbackCallbackServer(redirectURI: "http://example.com:1455/auth/callback") == nil)
    #expect(LoopbackCallbackServer(redirectURI: "http://localhost/auth/callback") == nil)
}

@Test func codexOAuthConfigMatchesWhatWasReadFromTheCLI() {
    // Pinned so a typo in the client id shows up here rather than as an opaque OAuth error.
    #expect(OAuthConfig.codex.clientID == "app_EMoamEEZ73f0CkXaXp7hrann")
    #expect(OAuthConfig.codex.redirectURI == "http://localhost:1455/auth/callback")
    #expect(OAuthConfig.codex.scopes.contains("offline_access"))   // no refresh token without it
    #expect(OAuthEndpoints.openAI.authorizeBase.host == "auth.openai.com")
}

// MARK: What is actually on offer

@Test func claudeAndCodexAreOffered() {
    #expect(Provider.selectableCases == [.claude, .codex])
    #expect(Provider.codex.isSupported)
    #expect(Provider.cursor.isSupported == false)
    // Every disabled provider must be able to say why; a greyed-out row with no reason is
    // indistinguishable from a bug.
    for p in Provider.allCases where !p.isSupported {
        #expect(p.unsupportedReason?.isEmpty == false)
    }
}

@Test func theCodexPathIsWired() {
    #expect(OAuthConfig.codex.clientID.isEmpty == false)
    #expect(OAuthEndpoints.openAI.tokenHosts.isEmpty == false)
    #expect(LoopbackCallbackServer(redirectURI: OAuthConfig.codex.redirectURI) != nil)
    #expect(CodexUsageAPIClient.endpoint.absoluteString
            == "https://chatgpt.com/backend-api/wham/usage")
}
