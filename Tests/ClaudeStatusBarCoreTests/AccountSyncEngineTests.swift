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

private final class Counter { var n = 0 }

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

@Test func test_unauthorized_reactiveRefresh_succeeds() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    // Non-expiring token: no PROACTIVE refresh; this exercises the REACTIVE path.
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let body = try usageBody()
    let counter = Counter()
    let http = MockHTTPClient { req in
        if req.url!.path.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, headers: [:], body: Data(
                #"{"access_token":"NEW","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
        }
        counter.n += 1
        if counter.n == 1 {
            return HTTPResponse(status: 401, headers: [:], body: Data())
        }
        return HTTPResponse(status: 200, headers: [:], body: body)
    }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    guard case .success(let snap) = out else {
        Issue.record("unexpected: \(out)")
        return
    }
    #expect(snap.session.utilization == 33.0)
    #expect(try store.load(id)?.accessToken == "NEW") // reactive refresh persisted
}

@Test func test_unauthorized_reactiveRefreshFails_needsReauth() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let http = MockHTTPClient { req in
        if req.url!.path.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 500, headers: [:], body: Data())
        }
        return HTTPResponse(status: 401, headers: [:], body: Data())
    }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    #expect(out == .needsReauth)
}

@Test func test_serverError_returnsOffline() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 500, headers: [:], body: Data()) }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    #expect(out == .offline)
}

@Test func test_decodingError_returnsFailed() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let malformedURL = try #require(Bundle.module.url(
        forResource: "usage_malformed", withExtension: "json", subdirectory: "Fixtures"))
    let body = try Data(contentsOf: malformedURL)
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 200, headers: [:], body: body) }
    let e = engine(http, clock: clock, store: store)
    let out = await e.syncOnce(accountID: id)
    #expect(out == .failed("decoding"))
}
