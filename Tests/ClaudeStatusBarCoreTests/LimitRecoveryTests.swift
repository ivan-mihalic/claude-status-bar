// Tests/ClaudeStatusBarCoreTests/LimitRecoveryTests.swift
//
// Running into a usage limit must never look like a broken login. These cover the
// path from the HTTP response, through the sync engine, to the reset time the app
// schedules its next attempt for.
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

private final class Counter { var n = 0 }

private func storedToken(_ store: TokenStore, _ id: UUID, expiresAt: TimeInterval = 100_000) throws {
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
                               expiresAt: .init(timeIntervalSince1970: expiresAt), scopes: []), for: id)
}

// MARK: - Retry-After parsing

@Test func retryAfter_parsesSecondsMillisecondsAndHTTPDate() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(RetryAfter.seconds(from: ["Retry-After": "120"], now: now) == 120)
    // Header names are case-insensitive on the wire.
    #expect(RetryAfter.seconds(from: ["retry-after": "45"], now: now) == 45)
    // The non-standard millisecond header is more precise, so it wins.
    #expect(RetryAfter.seconds(from: ["retry-after-ms": "2500", "retry-after": "9"], now: now) == 2.5)
    // HTTP-date form.
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "GMT")
    fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    let date = fmt.string(from: now.addingTimeInterval(300))
    #expect(RetryAfter.seconds(from: ["Retry-After": date], now: now) == 300)
}

@Test func retryAfter_ignoresMissingOrNonsenseValues() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(RetryAfter.seconds(from: [:], now: now) == nil)
    #expect(RetryAfter.seconds(from: ["Retry-After": "soon"], now: now) == nil)
    // A date already in the past means "retry now", not a negative wait.
    #expect(RetryAfter.seconds(from: ["Retry-After": "-30"], now: now) == nil)
}

// MARK: - HTTP layer

@Test func fetch_maps403ToForbidden_notUnauthorized() async {
    let http = MockHTTPClient { _ in HTTPResponse(status: 403, headers: [:], body: Data()) }
    let client = UsageAPIClient(http: http, userAgent: "ua")
    await #expect(throws: UsageAPIError.forbidden) {
        _ = try await client.fetch(accessToken: "x", now: Date())
    }
}

@Test func fetch_429_carriesRetryAfter() async {
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 429, headers: ["Retry-After": "90"], body: Data()) }
    let client = UsageAPIClient(http: http, userAgent: "ua")
    await #expect(throws: UsageAPIError.rateLimited(retryAfter: 90)) {
        _ = try await client.fetch(accessToken: "x", now: Date())
    }
}

// MARK: - Sync engine: a limit is not a login problem

/// The reported bug: hitting a limit made the app demand a fresh sign-in. A 401 sends
/// the engine down the refresh path; if the *retry* then hits the limit (429), the old
/// blanket `catch` reported `.needsReauth`.
@Test func syncOnce_refreshSucceedsButRetryIsRateLimited_reportsRateLimited() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try storedToken(store, id)
    let usageCalls = Counter()
    let http = MockHTTPClient { req in
        if req.url!.path.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, headers: [:], body: Data(
                #"{"access_token":"NEW","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
        }
        usageCalls.n += 1
        return usageCalls.n == 1
            ? HTTPResponse(status: 401, headers: [:], body: Data())
            : HTTPResponse(status: 429, headers: ["Retry-After": "600"], body: Data())
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .rateLimited(retryAfter: 600))
}

@Test func syncOnce_forbidden_isRateLimited_andNeverRefreshesTheToken() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try storedToken(store, id)
    let http = MockHTTPClient { _ in HTTPResponse(status: 403, headers: [:], body: Data()) }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .rateLimited(retryAfter: nil))
    // 403 is a permission decision, not a stale token: burning a refresh (and the
    // rotated refresh token that comes with it) on every poll is what eventually
    // broke the grant for real.
    #expect(!http.requests.contains { $0.url!.path.hasSuffix("/oauth/token") })
    #expect(try store.load(id)?.accessToken == "AT")
}

@Test func syncOnce_refreshFailsOnNetwork_isOffline_notNeedsReauth() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    // Expiring token forces the proactive refresh path.
    try storedToken(store, id, expiresAt: 100)
    struct Boom: Error {}
    let http = MockHTTPClient { _ in throw Boom() }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .offline)
}

@Test func syncOnce_refreshRejectedAsInvalidGrant_needsReauth() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try storedToken(store, id, expiresAt: 100)
    let http = MockHTTPClient { _ in HTTPResponse(status: 400, headers: [:], body: Data()) }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .needsReauth)
}

@Test func syncOnce_stillUnauthorizedAfterRefresh_needsReauth() async throws {
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try storedToken(store, id)
    let http = MockHTTPClient { req in
        req.url!.path.hasSuffix("/oauth/token")
            ? HTTPResponse(status: 200, headers: [:], body: Data(
                #"{"access_token":"NEW","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
            : HTTPResponse(status: 401, headers: [:], body: Data())
    }
    let out = await engine(http, clock: clock, store: store).syncOnce(accountID: id)
    #expect(out == .needsReauth)
}

// MARK: - Knowing when the limit lifts

private func window(_ key: String, _ u: Double, resetsAt: TimeInterval) -> UsageWindow {
    UsageWindow(key: key, label: key, utilization: u, resetsAt: .init(timeIntervalSince1970: resetsAt))
}

@Test func nextResetForExhaustedWindow_picksEarliestFutureResetAmongMaxedWindows() {
    let now = Date(timeIntervalSince1970: 1000)
    let snap = UsageSnapshot(
        session: window("five_hour", 100, resetsAt: 5000),
        weekAll: window("seven_day", 100, resetsAt: 3000),
        weekPremium: [window("seven_day_opus", 12, resetsAt: 2000)],   // not exhausted
        fetchedAt: now)
    #expect(snap.nextResetForExhaustedWindow(now: now) == Date(timeIntervalSince1970: 3000))
}

@Test func nextResetForExhaustedWindow_nilWhenNothingIsExhaustedOrResetsArePast() {
    let now = Date(timeIntervalSince1970: 1000)
    let none = UsageSnapshot(session: window("five_hour", 40, resetsAt: 5000),
                             weekAll: window("seven_day", 88, resetsAt: 6000),
                             weekPremium: [], fetchedAt: now)
    #expect(none.nextResetForExhaustedWindow(now: now) == nil)

    let past = UsageSnapshot(session: window("five_hour", 100, resetsAt: 500),
                             weekAll: window("seven_day", 100, resetsAt: 900),
                             weekPremium: [], fetchedAt: now)
    #expect(past.nextResetForExhaustedWindow(now: now) == nil)
}

// MARK: - Scheduling

@Test func nextInterval_rateLimited_isCappedSoALongResetStillGetsRechecked() {
    let now = Date(timeIntervalSince1970: 1000)
    // A weekly limit can reset days out; sleeping that long would strand the account
    // if the reset time were ever wrong. Re-check at least hourly.
    let dt = SyncScheduler.nextInterval(
        base: 300,
        status: .rateLimited(retryAt: now.addingTimeInterval(5 * 24 * 3600)),
        consecutiveRateLimits: 2, now: now)
    #expect(dt == SyncScheduler.maxRateLimitedInterval)
    #expect(dt == 3600)
}
