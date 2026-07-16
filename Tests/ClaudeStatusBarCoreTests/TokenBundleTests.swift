import Testing
import Foundation
@testable import ClaudeStatusBarCore

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
    let b = resp.bundle(now: now)
    #expect(b.accessToken == "AT")
    #expect(b.refreshToken == "RT")
    #expect(b.expiresAt == Date(timeIntervalSince1970: 28800))
    #expect(b.scopes == ["user:profile"])
}
