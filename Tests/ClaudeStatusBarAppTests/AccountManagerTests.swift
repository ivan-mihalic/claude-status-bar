// Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift
import Testing
import Foundation
import TestSupport
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@MainActor
private func makeManager(_ http: MockHTTPClient, store: TokenStore, snapURL: URL)
-> (AccountManager, AppState) {
    let state = AppState()
    let login = OAuthLoginService(
        oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode,
                           clock: ManualClock(Date(timeIntervalSince1970: 0))),
        endpoints: .production, config: .claudeCode, tokenStore: store, opener: SpyBrowser())
    let mgr = AccountManager(appState: state, login: login, tokenStore: store,
                             snapshotStore: SnapshotStore(fileURL: snapURL))
    return (mgr, state)
}

@Test @MainActor func finishAdd_createsPersistsAndAppendsAccount() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let pending = mgr.beginLogin()!
    let acct = try await mgr.finishAdd(pending, code: "CODE", label: "work@x")
    #expect(state.accounts.count == 1)
    #expect(acct.label == "work@x")
    #expect(acct.syncInterval == 300)
    #expect(try store.load(acct.id) != nil)                         // token stored
    #expect(try SnapshotStore(fileURL: tmp).load().first?.id == acct.id) // metadata persisted
}

@Test @MainActor func finishAdd_withInterval_usesCustomSyncInterval() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, _) = makeManager(http, store: store, snapURL: tmp)
    let pending = mgr.beginLogin()!
    let acct = try await mgr.finishAdd(pending, code: "CODE", label: "work@x", interval: 600)
    #expect(acct.syncInterval == 600)
}

/// Mutable call counter for handlers that must answer differently per request.
private final class Counter { var n = 0 }

private func tokenResponse(_ access: String) -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data(
        #"{"access_token":"\#(access)","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8))
}

@Test @MainActor func reauth_replacesTokenInPlace_withoutAddingATile() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let calls = Counter()
    let http = MockHTTPClient { _ in calls.n += 1; return tokenResponse(calls.n == 1 ? "AT1" : "AT2") }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let acct = try await mgr.finishAdd(mgr.beginLogin()!, code: "C1", label: "work@x", interval: 600)
    mgr.setPrefix(acct.id, "W:")
    // The account has since expired and shows "Sign in again".
    var stale = state.accounts[0]
    stale.status = .needsReauth
    stale.lastSnapshot = nil
    state.upsert(stale)

    try await mgr.reauth(acct.id, mgr.beginLogin()!, code: "C2")

    #expect(state.accounts.count == 1)                       // no second tile
    #expect(state.accounts[0].id == acct.id)                 // same account…
    #expect(state.accounts[0].label == "work@x")             // …keeps its settings
    #expect(state.accounts[0].menuBarPrefix == "W:")
    #expect(state.accounts[0].syncInterval == 600)
    #expect(state.accounts[0].status == .never)              // syncing again, not needsReauth
    #expect(try store.load(acct.id)?.accessToken == "AT2")   // fresh token under the SAME id
    #expect(try SnapshotStore(fileURL: tmp).load().count == 1)
}

@Test @MainActor func reauth_unknownAccount_throwsAndStoresNoToken() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in tokenResponse("AT") }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let ghost = UUID()
    await #expect(throws: AccountError.unknownAccount) {
        try await mgr.reauth(ghost, mgr.beginLogin()!, code: "C")
    }
    #expect(state.accounts.isEmpty)
    #expect(try store.load(ghost) == nil)
}

@Test @MainActor func move_reordersAccountsAndPersistsTheNewOrder() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let http = MockHTTPClient { _ in tokenResponse("AT") }
    let (mgr, state) = makeManager(http, store: InMemoryTokenStore(), snapURL: tmp)
    let a = try await mgr.finishAdd(mgr.beginLogin()!, code: "C", label: "a")
    let b = try await mgr.finishAdd(mgr.beginLogin()!, code: "C", label: "b")
    _ = b
    mgr.move(a.id, by: 1)
    #expect(state.accounts.map(\.label) == ["b", "a"])
    #expect(try SnapshotStore(fileURL: tmp).load().map(\.label) == ["b", "a"])
}

@Test @MainActor func remove_deletesTokenAndPersists() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let acct = try await mgr.finishAdd(mgr.beginLogin()!, code: "C", label: "x")
    mgr.remove(acct.id)
    #expect(state.accounts.isEmpty)
    #expect(try store.load(acct.id) == nil)
    #expect(try SnapshotStore(fileURL: tmp).load().isEmpty)
}

@Test @MainActor func setRingColor_updatesTheLiveAccountAndPersistsIt() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let http = MockHTTPClient { _ in tokenResponse("AT") }
    let (mgr, state) = makeManager(http, store: InMemoryTokenStore(), snapURL: tmp)
    let account = try await mgr.finishAdd(mgr.beginLogin()!, code: "C", label: "x")
    let colour = AccountRingColor(red: 0.7, green: 0.2, blue: 0.4)

    mgr.setRingColor(account.id, colour)

    #expect(state.accounts.first?.ringColor == colour)
    #expect(try SnapshotStore(fileURL: tmp).load().first?.ringColor == colour)
    #expect(NotchModel.ring(for: state.accounts[0]).ringColor == colour)
}
