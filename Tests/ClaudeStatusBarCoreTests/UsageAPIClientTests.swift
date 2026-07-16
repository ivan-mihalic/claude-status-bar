import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func body(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func fetch_setsAuthAndBetaHeaders_andReturnsSnapshot() async throws {
    let http = MockHTTPClient()
    http.handler = { _ in HTTPResponse(status: 200, headers: [:], body: try body("usage_full")) }
    let client = UsageAPIClient(http: http, userAgent: "claude-code/1.0.0")
    let snap = try await client.fetch(accessToken: "AT",
                                      now: .init(timeIntervalSince1970: 0))
    #expect(snap.session.utilization == 33.0)
    let req = try #require(http.lastRequest)
    #expect(req.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
    #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(req.value(forHTTPHeaderField: "User-Agent") == "claude-code/1.0.0")
}

@Test func fetch_maps401ToUnauthorized() async {
    let http = MockHTTPClient { _ in HTTPResponse(status: 401, headers: [:], body: Data()) }
    let client = UsageAPIClient(http: http, userAgent: "ua")
    await #expect(throws: UsageAPIError.unauthorized) {
        _ = try await client.fetch(accessToken: "x", now: Date())
    }
}

@Test func fetch_maps429ToRateLimited() async {
    let http = MockHTTPClient { _ in HTTPResponse(status: 429, headers: [:], body: Data()) }
    let client = UsageAPIClient(http: http, userAgent: "ua")
    await #expect(throws: UsageAPIError.rateLimited) {
        _ = try await client.fetch(accessToken: "x", now: Date())
    }
}
