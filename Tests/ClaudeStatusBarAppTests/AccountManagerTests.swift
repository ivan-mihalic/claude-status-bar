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
                             snapshotStore: SnapshotStore(fileURL: snapURL),
                             importer: nil)
    return (mgr, state)
}

@Test @MainActor func finishAdd_createsPersistsAndAppendsAccount() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let pending = mgr.beginAdd(label: nil)
    let acct = try await mgr.finishAdd(pending, code: "CODE", label: "work@x")
    #expect(state.accounts.count == 1)
    #expect(acct.label == "work@x")
    #expect(acct.syncInterval == 300)
    #expect(try store.load(acct.id) != nil)                         // token stored
    #expect(try SnapshotStore(fileURL: tmp).load().first?.id == acct.id) // metadata persisted
}

@Test @MainActor func remove_deletesTokenAndPersists() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:],
        body: Data(#"{"access_token":"AT","refresh_token":"RT","expires_in":28800,"scope":""}"#.utf8)) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let acct = try await mgr.finishAdd(mgr.beginAdd(label: nil), code: "C", label: "x")
    mgr.remove(acct.id)
    #expect(state.accounts.isEmpty)
    #expect(try store.load(acct.id) == nil)
    #expect(try SnapshotStore(fileURL: tmp).load().isEmpty)
}
