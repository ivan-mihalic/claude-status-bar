import Testing
import Foundation
@testable import ClaudeStatusBarCore
import TestSupport

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

// Nedostupnost Keychain se nesmí zaměnit za chybějící přihlášení.
private final class UnreadableTokenStore: TokenStore, @unchecked Sendable {
    let inner = InMemoryTokenStore()
    private let lock = NSLock()
    private let failingLoads: Set<Int>
    private var loadCount = 0

    init(failingLoads: Set<Int>) { self.failingLoads = failingLoads }

    func load(_ id: UUID) throws -> TokenBundle? {
        lock.lock()
        loadCount += 1
        let fail = failingLoads.contains(loadCount)
        lock.unlock()
        if fail { throw KeychainError.status(-25308) }
        return try inner.load(id)
    }

    func save(_ bundle: TokenBundle, for id: UUID) throws { try inner.save(bundle, for: id) }
    func delete(_ id: UUID) throws { try inner.delete(id) }
}

@Test func test_keychainReadFailure_reportsFailureThenRecoversWithoutLogin() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = UnreadableTokenStore(failingLoads: [1])
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let body = try usageBody()
    let http = MockHTTPClient { req in
        #expect(req.url == UsageAPIClient.endpoint)
        return HTTPResponse(status: 200, headers: [:], body: body)
    }
    let e = engine(http, clock: clock, store: store)
    let first = await e.syncOnce(accountID: id)
    guard case .failed(let reason) = first else {
        Issue.record("chyba čtení Keychain není odhlášení: \(first)")
        return
    }
    #expect(reason.contains("-25308"))
    let second = await e.syncOnce(accountID: id)
    guard case .success = second else {
        Issue.record("další sync se musí zotavit bez přihlášení: \(second)")
        return
    }
    #expect(try store.inner.load(id)?.accessToken == "AT")
}

@Test func test_keychainReadFailureDuringRefresh_retriesWithoutSpendingStaleToken() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = UnreadableTokenStore(failingLoads: [2])
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: .init(timeIntervalSince1970: 100), scopes: []), for: id)
    let body = try usageBody()
    let counter = Counter()
    let http = MockHTTPClient { req in
        counter.n += 1
        if req.url!.path.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, headers: [:], body: Data(
                #"{"access_token":"NEW","refresh_token":"RT2","expires_in":28800}"#.utf8))
        }
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer NEW")
        return HTTPResponse(status: 200, headers: [:], body: body)
    }
    let e = engine(http, clock: clock, store: store)
    let first = await e.syncOnce(accountID: id)
    guard case .failed = first else {
        Issue.record("nedostupné úložiště při refreshi se musí oznámit: \(first)")
        return
    }
    #expect(counter.n == 0)
    let second = await e.syncOnce(accountID: id)
    guard case .success = second else {
        Issue.record("refresh se musí zotavit bez přihlášení: \(second)")
        return
    }
    #expect(counter.n == 2)
    #expect(try store.inner.load(id)?.refreshToken == "RT2")
}

@Test func test_missingToken_returnsNeedsReauth() async {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let http = MockHTTPClient()
    let e = engine(http, clock: clock, store: InMemoryTokenStore())
    let out = await e.syncOnce(accountID: UUID())
    #expect(out == .needsReauth)
}

@Test func test_accessOnlyToken_nearExpiryFetchesWithoutRefresh() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "",
        expiresAt: .init(timeIntervalSince1970: 100), scopes: []), for: id)
    let body = try usageBody()
    let http = MockHTTPClient { req in
        #expect(req.url == UsageAPIClient.endpoint, "token bez refresh tokenu se neobnovuje")
        return HTTPResponse(status: 200, headers: [:], body: body)
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    guard case .success = out else {
        Issue.record("dosud platný access-only token musí fungovat: \(out)")
        return
    }
}

@Test func test_accessOnlyToken_unauthorizedRequiresReplacementWithoutRefresh() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "",
        expiresAt: .distantFuture, scopes: []), for: id)
    let http = MockHTTPClient { req in
        #expect(req.url == UsageAPIClient.endpoint)
        return HTTPResponse(status: 401, headers: [:], body: Data())
    }
    #expect(await engine(http, clock: clock, store: store).syncOnce(accountID: id) == .needsReauth)
}

@Test func test_accessOnlyToken_forbiddenReportsUsagePermissionInsteadOfRateLimit() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "",
        expiresAt: .distantFuture, scopes: []), for: id)
    let http = MockHTTPClient { req in
        #expect(req.url == UsageAPIClient.endpoint)
        return HTTPResponse(status: 403, headers: [:], body: Data())
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    guard case .failed(let reason) = out else {
        Issue.record("odmítnutý importovaný token musí mít vysvětlení: \(out)")
        return
    }
    #expect(reason.contains("usage"))
    #expect(reason.contains("user:profile"))
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
    #expect(snap.session?.utilization == 33.0)
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
    #expect(out == .rateLimited(retryAfter: nil))
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
    #expect(snap.session?.utilization == 33.0)
    #expect(try store.load(id)?.accessToken == "NEW") // reactive refresh persisted
}

@Test func test_unauthorized_reactiveRefreshUnreachable_isOffline() async throws {
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
    // A token host that is merely down says nothing about the grant — see
    // syncOnce_refreshRejectedAsInvalidGrant_needsReauth for the real reauth case.
    #expect(out == .offline)
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
