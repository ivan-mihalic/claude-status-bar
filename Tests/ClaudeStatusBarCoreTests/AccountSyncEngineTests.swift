import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func engine(_ http: MockHTTPClient, clock: ManualClock,
                     store: TokenStore) -> AccountSyncEngine {
    AccountSyncEngine(
        tokenStore: store,
        oauth: OAuthClient(http: http, endpoints: .production,
                           config: .claudeCode, clock: clock),
        usage: UsageAPIClient(http: http, userAgent: "ua"),
        clock: clock, refreshWindow: 300)
}

private func usageBody() throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func test_missingToken_returnsNeedsReauth() async {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let http = MockHTTPClient()
    let e = engine(http, clock: clock, store: InMemoryTokenStore())
    let out = await e.syncOnce(accountID: UUID())
    #expect(out == .needsReauth)
}

@Test func test_validToken_success() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let body = try usageBody()
    let http = MockHTTPClient { req in
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
        return HTTPResponse(status: 200, headers: [:], body: body)
    }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    guard case .success(let snap) = out else {
        Issue.record("unexpected: \(out)")
        return
    }
    #expect(snap.session.utilization == 33.0)
}

@Test func test_expiringToken_refreshesThenFetches() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    // expiresAt within refreshWindow (300s) -> must refresh first
    try store.save(TokenBundle(accessToken: "OLD", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100), scopes: []), for: id)
    let body = try usageBody()
    let http = MockHTTPClient { req in
        if req.url!.path.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, headers: [:], body: Data(
                #"{"access_token":"NEW","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
        }
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer NEW")
        return HTTPResponse(status: 200, headers: [:], body: body)
    }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    guard case .success = out else {
        Issue.record("unexpected: \(out)")
        return
    }
    #expect(try store.load(id)?.accessToken == "NEW") // persisted
}

@Test func test_429_returnsRateLimited() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 429, headers: [:], body: Data()) }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    #expect(out == .rateLimited)
}
