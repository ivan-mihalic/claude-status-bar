// Tests/ClaudeStatusBarAppTests/SyncCoordinatorTests.swift
import Testing
import Foundation
import TestSupport
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@MainActor
private func coord(_ http: MockHTTPClient, _ state: AppState, _ store: TokenStore,
                   _ clock: ManualClock, _ snapURL: URL) -> SyncCoordinator {
    SyncCoordinator(
        appState: state,
        engine: AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http), clock: clock),
        clock: clock,
        snapshotStore: SnapshotStore(fileURL: snapURL))
}

@Test @MainActor func syncNow_success_updatesAccountAndPersists() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: Date(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let state = AppState()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                         status: .never, lastSnapshot: nil, lastSyncedAt: nil))
    let usage = try! Data(contentsOf: Bundle.module.url(forResource: "usage_full",
        withExtension: "json", subdirectory: "Fixtures")!)   // see step note
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:], body: usage) }
    let c = coord(http, state, store, clock, tmp)
    await c.syncNow(id)
    #expect(state.accounts.first?.status == .ok)
    #expect(state.accounts.first?.lastSnapshot?.session?.utilization == 33.0)
}

@Test @MainActor func syncNow_accountRemovedMidSync_doesNotResurrectIt() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
        expiresAt: Date(timeIntervalSince1970: 100_000), scopes: []), for: id)
    let state = AppState()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                         status: .never, lastSnapshot: nil, lastSyncedAt: nil))
    let usage = try! Data(contentsOf: Bundle.module.url(forResource: "usage_full",
        withExtension: "json", subdirectory: "Fixtures")!)
    // Simulate the user hitting "Remove" while the request is in flight: the handler
    // removes the account from appState, THEN the (now stale) response arrives.
    let http = MockHTTPClient { _ in
        state.remove(id)
        return HTTPResponse(status: 200, headers: [:], body: usage)
    }
    let c = coord(http, state, store, clock, tmp)
    await c.syncNow(id)
    #expect(state.accounts.isEmpty)
}

@Test @MainActor func nextDelay_rateLimited_usesRetryAt() async {
    let clock = ManualClock(Date(timeIntervalSince1970: 1000))
    let state = AppState()
    let id = UUID()
    state.upsert(Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
        status: .rateLimited(retryAt: Date(timeIntervalSince1970: 1000 + 200)),
        lastSnapshot: nil, lastSyncedAt: nil))
    let c = coord(MockHTTPClient(), state, InMemoryTokenStore(), clock, URL(fileURLWithPath: "/dev/null"))
    #expect(c.nextDelay(for: id, now: clock.now()) == 200)
}

@MainActor
@Test func syncNow_selfInflictedFailure_isSurfacedNotJustShownAsOffline() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let clock = ManualClock(.init(timeIntervalSince1970: 0))
    let store = InMemoryTokenStore()
    let id = UUID()
    try store.save(TokenBundle(accessToken: "OLD", refreshToken: "RT",
                               expiresAt: .init(timeIntervalSince1970: 100),
                               scopes: []), for: id)
    let http = MockHTTPClient { _ in
        HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"access_token":"AT2","refresh_token":"RT2","expires_in":28800,"scope":""}"#.utf8))
    }
    // A store that refuses writes: the refresh succeeds, the rotation can't be kept.
    struct Unwritable: TokenStore {
        let inner: InMemoryTokenStore
        func save(_ bundle: TokenBundle, for id: UUID) throws { throw KeychainError.status(-25308) }
        func load(_ id: UUID) throws -> TokenBundle? { try inner.load(id) }
        func delete(_ id: UUID) throws { try inner.delete(id) }
    }
    let state = AppState()
    state.upsert(Account(id: id, label: "Work", accountUuid: nil,
                         syncInterval: 300, status: .ok,
                         lastSnapshot: nil, lastSyncedAt: nil))
    let engine = AccountSyncEngine(
        tokenStore: Unwritable(inner: store),
        oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode, clock: clock),
        usage: UsageAPIClient(http: http, userAgent: "ua"), clock: clock)
    let coordinator = SyncCoordinator(appState: state, engine: engine, clock: clock,
                                      snapshotStore: SnapshotStore(fileURL: tmp))
    await coordinator.syncNow(id)

    let message = try #require(state.lastError)
    #expect(message.contains("Work"))
}
