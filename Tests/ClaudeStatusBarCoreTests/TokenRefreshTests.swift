import Testing
import Foundation
@testable import ClaudeStatusBarCore
import TestSupport

// Reprodukce tří cest, kterými se účet odhlásí, aniž by jeho grant opravdu zanikl.

private func usageBody() throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func engine(_ http: MockHTTPClient, clock: ManualClock,
                    store: TokenStore) -> AccountSyncEngine {
    AccountSyncEngine(
        tokenStore: store,
        oauth: OAuthClient(http: http, endpoints: .production,
                           config: .claudeCode, clock: clock),
        usage: UsageAPIClient(http: http, userAgent: "ua"),
        clock: clock, refreshWindow: 300)
}

private func expiringBundle() -> TokenBundle {
    TokenBundle(accessToken: "OLD", refreshToken: "RT1",
                expiresAt: .init(timeIntervalSince1970: 100), scopes: [])
}

/// A server that rotates the refresh token: `RT1` works exactly once, and a second
/// presentation of it is `invalid_grant` — the shape that signs the account out.
private final class RotatingTokenServer: @unchecked Sendable {
    private let lock = NSLock()
    private var used = Set<String>()
    private(set) var refreshCount = 0
    let usage: Data
    init(usage: Data) { self.usage = usage }

    func respond(_ req: URLRequest) -> HTTPResponse {
        guard req.url!.path.contains("oauth/token") else {
            return HTTPResponse(status: 200, headers: [:], body: usage)
        }
        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        let token = body.contains("refresh_token=RT1") ? "RT1" : "?"
        lock.lock(); defer { lock.unlock() }
        refreshCount += 1
        if used.contains(token) {
            return HTTPResponse(status: 400, headers: [:],
                                body: Data(#"{"error":"invalid_grant"}"#.utf8))
        }
        used.insert(token)
        return HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"access_token":"AT2","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
    }
}

@Test func test_concurrentSyncs_doNotRaceForTheRotatedRefreshToken() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(expiringBundle(), for: id)
    let server = RotatingTokenServer(usage: try usageBody())
    let http = MockHTTPClient { server.respond($0) }
    let e = engine(http, clock: clock, store: store)

    async let a = e.syncOnce(accountID: id)
    async let b = e.syncOnce(accountID: id)
    let outcomes = await [a, b]

    #expect(!outcomes.contains(.needsReauth),
            "souběžný sync nesmí účet odhlásit: \(outcomes)")
    #expect(server.refreshCount == 1,
            "jeden účet = jeden refresh, ne \(server.refreshCount)")
}

@Test func test_400ThatIsNotInvalidGrant_doesNotSignOut() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(expiringBundle(), for: id)
    let http = MockHTTPClient { req in
        guard req.url!.path.contains("oauth/token") else {
            return HTTPResponse(status: 200, headers: [:], body: Data())
        }
        // RFC 6749 §5.2 — 400 s jinou chybou než invalid_grant. Grant žije dál.
        return HTTPResponse(status: 400, headers: [:],
                            body: Data(#"{"error":"invalid_request"}"#.utf8))
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .offline, "400 invalid_request není mrtvý grant, dostal: \(out)")
}

@Test func test_invalidGrant_stillSignsOut() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(expiringBundle(), for: id)
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 400, headers: [:],
                     body: Data(#"{"error":"invalid_grant"}"#.utf8))
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .needsReauth)
}

/// A store whose writes fail — the shape that silently loses a rotated refresh token.
private final class FailingWriteTokenStore: TokenStore, @unchecked Sendable {
    private let inner = InMemoryTokenStore()
    private let lock = NSLock()
    var failWrites = true
    private(set) var saveAttempts = 0
    func save(_ bundle: TokenBundle, for id: UUID) throws {
        lock.lock(); saveAttempts += 1; let fail = failWrites; lock.unlock()
        if fail { throw KeychainError.status(-25308) }
        try inner.save(bundle, for: id)
    }
    func load(_ id: UUID) throws -> TokenBundle? { try inner.load(id) }
    func delete(_ id: UUID) throws { try inner.delete(id) }
    func seed(_ bundle: TokenBundle, for id: UUID) throws { try inner.save(bundle, for: id) }
}

@Test func test_unwritableStore_isReported_andRotatedTokenIsNotLost() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = FailingWriteTokenStore()
    let id = UUID()
    try store.seed(expiringBundle(), for: id)
    let server = RotatingTokenServer(usage: try usageBody())
    let http = MockHTTPClient { server.respond($0) }
    let e = engine(http, clock: clock, store: store)

    let first = await e.syncOnce(accountID: id)
    guard case .failed = first else {
        Issue.record("selhaný zápis tokenu se nesmí spolknout, dostal: \(first)")
        return
    }
    // The rotated token must survive in memory: the next sync may not present RT1 again
    // (the server would answer invalid_grant and the account would be signed out).
    let second = await e.syncOnce(accountID: id)
    #expect(second != .needsReauth,
            "po selhaném zápisu se nesmí znovu poslat starý refresh token")
}

@Test func test_400WithAnUnreadableBody_isRetriedNotSignedOut() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(expiringBundle(), for: id)
    // An empty 400 names no OAuth error, so it proves nothing about the grant.
    let http = MockHTTPClient { _ in HTTPResponse(status: 400, headers: [:], body: Data()) }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .offline)
}

@Test func test_invalidGrantInAWrappedBody_stillSignsOut() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(expiringBundle(), for: id)
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 400, headers: [:],
                     body: Data(#"{"error":{"type":"invalid_grant"}}"#.utf8))
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .needsReauth)
}
