// Tests/ClaudeStatusBarAppTests/StaleSyncClobberTests.swift
//
// Reproduces the "one account is stuck offline and Sync doesn't bring it back"
// report: the background poll for that account is still in flight (a request that
// hangs after the Mac wakes with a half-up network), the user clicks Sync, the
// manual fetch succeeds — and then the *older* request finally fails and writes
// `.offline` over the newer success. The tile flips back on its own with no further
// interaction, and clicking Sync again just repeats the race.
import Testing
import Foundation
import TestSupport
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

/// Answers the first request only after `release()` and then fails it; every later
/// request succeeds immediately. Models a slow request that outlives a fast one.
private actor SlowFirstHTTPClient: HTTPClient {
    private let body: Data
    private var started = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false

    init(body: Data) { self.body = body }

    var startedCount: Int { started }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        started += 1
        if started == 1 {
            if !released { await withCheckedContinuation { waiter = $0 } }
            throw URLError(.notConnectedToInternet)
        }
        return HTTPResponse(status: 200, headers: [:], body: body)
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}

@MainActor
private func coordinator(_ http: HTTPClient, _ state: AppState, _ store: TokenStore,
                         _ clock: ManualClock, _ snapURL: URL) -> SyncCoordinator {
    SyncCoordinator(
        appState: state,
        engine: AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production,
                               config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http), clock: clock),
        clock: clock,
        snapshotStore: SnapshotStore(fileURL: snapURL))
}

@Test @MainActor
func manualSyncSuccess_survivesStaleInFlightFailure() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    // Far-future expiry: no token refresh, so each sync is exactly one usage request.
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
                               expiresAt: Date(timeIntervalSince1970: 100_000),
                               scopes: []), for: id)
    let state = AppState()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                         status: .never, lastSnapshot: nil, lastSyncedAt: nil))

    let usage = try #require(Bundle.module.url(forResource: "usage_full",
                                               withExtension: "json",
                                               subdirectory: "Fixtures"))
    let http = SlowFirstHTTPClient(body: try Data(contentsOf: usage))
    let c = coordinator(http, state, store, clock, tmp)

    // 1. The scheduled poll starts and hangs mid-request.
    let background = Task { await c.syncNow(id) }
    while await http.startedCount == 0 { await Task.yield() }

    // 2. The user clicks Sync; that fetch succeeds.
    await c.syncNow(id)
    #expect(state.accounts.first?.status == .ok)

    // 3. The stale request finally gives up.
    await http.release()
    await background.value

    // The account must stay online: a failure that started *before* the successful
    // fetch says nothing about the state after it.
    #expect(state.accounts.first?.status == .ok)
    #expect(state.accounts.first?.lastSnapshot != nil)
}

/// The same race the other way round, which must still work: a sync that starts
/// *after* the last applied result is authoritative even if an older one is pending.
@Test @MainActor
func laterFailure_stillMarksAccountOffline() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
                               expiresAt: Date(timeIntervalSince1970: 100_000),
                               scopes: []), for: id)
    let state = AppState()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                         status: .ok, lastSnapshot: nil, lastSyncedAt: nil))

    let http = MockHTTPClient { _ in throw URLError(.notConnectedToInternet) }
    let c = coordinator(http, state, store, clock, tmp)
    await c.syncNow(id)
    #expect(state.accounts.first?.status == .offline)
}
