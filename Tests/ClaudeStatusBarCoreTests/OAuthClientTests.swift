import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func ok(_ json: String) -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data(json.utf8))
}

@Test func exchange_decodesBundle() async throws {
    let http = MockHTTPClient { _ in
        ok(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":"user:profile"}"#)
    }
    let client = OAuthClient(http: http, endpoints: .production,
                             config: .claudeCode,
                             clock: ManualClock(Date(timeIntervalSince1970: 0)))
    let b = try await client.exchange(code: "C", verifier: "V", state: "S")
    #expect(b.accessToken == "AT")
    #expect(b.expiresAt == Date(timeIntervalSince1970: 28800))
}

@Test func refresh_fallsBackToSecondHost_onFirstHostFailure() async throws {
    let http = MockHTTPClient { req in
        if req.url!.host == "platform.claude.com" {
            return HTTPResponse(status: 500, headers: [:], body: Data())
        }
        return ok(#"{"access_token":"AT2","refresh_token":"RT2","expires_in":100,"scope":""}"#)
    }
    let client = OAuthClient(http: http, endpoints: .production,
                             config: .claudeCode,
                             clock: ManualClock(Date(timeIntervalSince1970: 0)))
    let b = try await client.refresh(
        TokenBundle(accessToken: "x", refreshToken: "RT",
                    expiresAt: .init(timeIntervalSince1970: 0), scopes: []))
    #expect(b.accessToken == "AT2")
}

@Test func exchange_throwsInvalidGrant_on400() async throws {
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 400, headers: [:],
                     body: Data(#"{"error":"invalid_grant"}"#.utf8))
    }
    let client = OAuthClient(http: http, endpoints: .production,
                             config: .claudeCode,
                             clock: ManualClock(.init(timeIntervalSince1970: 0)))
    await #expect(throws: OAuthError.invalidGrant) {
        _ = try await client.exchange(code: "C", verifier: "V", state: "S")
    }
}
