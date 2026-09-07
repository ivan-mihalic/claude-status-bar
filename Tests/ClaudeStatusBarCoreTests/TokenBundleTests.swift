import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func tokenJWT(accountID: String) -> String {
    let payload = Data(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"\#(accountID)"}}"#.utf8)
    return "header.\(Base64URL.encode(payload)).signature"
}

@Test func isExpiring_true_whenWithinWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let b = TokenBundle(accessToken: "a", refreshToken: "r",
                        expiresAt: now.addingTimeInterval(200), scopes: [])
    #expect(b.isExpiring(within: 300, now: now))
    #expect(!b.isExpiring(within: 100, now: now))
}

@Test func tokenResponse_computesExpiresAt() throws {
    let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":"user:profile"}"#
    let resp = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let now = Date(timeIntervalSince1970: 0)
    let b = resp.bundle(now: now, previousRefreshToken: "")
    #expect(b.accessToken == "AT")
    #expect(b.refreshToken == "RT")
    #expect(b.expiresAt == Date(timeIntervalSince1970: 28800))
    #expect(b.scopes == ["user:profile"])
}

@Test func tokenResponse_missingRefreshToken_keepsPrevious() throws {
    let json = #"{"access_token":"AT","expires_in":28800,"scope":"user:profile"}"#
    let resp = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let b = resp.bundle(now: Date(timeIntervalSince1970: 0), previousRefreshToken: "OLD_RT")
    #expect(b.refreshToken == "OLD_RT")
    #expect(b.accessToken == "AT")
}

@Test func tokenResponse_missingExpiresIn_usesDefaultLifetime() throws {
    let json = #"{"access_token":"AT","refresh_token":"RT"}"#
    let resp = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let b = resp.bundle(now: Date(timeIntervalSince1970: 0), previousRefreshToken: "X")
    #expect(b.expiresAt == Date(timeIntervalSince1970: 3600)) // 1h default
}

@Test func tokenResponse_readsTheChatGPTAccountFromTheIDToken() throws {
    let jwt = tokenJWT(accountID: "workspace-123")
    let json = #"{"access_token":"AT","refresh_token":"RT","id_token":"\#(jwt)"}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))

    #expect(response.bundle(now: Date(), previousRefreshToken: "").accountID == "workspace-123")
}

@Test func tokenResponse_keepsThePreviousAccountWhenARefreshOmitsIt() throws {
    let response = try JSONDecoder().decode(TokenResponse.self,
        from: Data(#"{"access_token":"opaque","refresh_token":"RT"}"#.utf8))

    #expect(response.bundle(now: Date(), previousRefreshToken: "OLD",
                            previousAccountID: "workspace-123").accountID == "workspace-123")
}

@Test func tokenBundle_decodesCredentialsSavedBeforeAccountRoutingWasAdded() throws {
    let json = #"{"accessToken":"AT","refreshToken":"RT","expiresAt":0,"scopes":[]}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    #expect(try decoder.decode(TokenBundle.self, from: Data(json.utf8)).accountID == nil)
}
