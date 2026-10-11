// Tests/ClaudeStatusBarAppTests/AccountManagerTests.swift
import Testing
import Foundation
import TestSupport
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@MainActor
private func makeManager(_ http: HTTPClient, store: TokenStore, snapURL: URL)
-> (AccountManager, AppState) {
    let state = AppState()
    let login = OAuthLoginService(
        oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode,
                           clock: ManualClock(Date(timeIntervalSince1970: 0))),
        endpoints: .production, config: .claudeCode, tokenStore: store, opener: SpyBrowser())
    let mgr = AccountManager(appState: state, login: login, tokenStore: store,
                             snapshotStore: SnapshotStore(fileURL: snapURL),
                             claudeValidation: ClaudeTokenValidation(usage: UsageAPIClient(http: http),
                                                                    clock: ManualClock(Date(timeIntervalSince1970: 0))))
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

@Test @MainActor func importClaudeToken_createsAccountAndKeepsSecretOutOfSnapshot() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let (mgr, state) = makeManager(MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:], body: try Data(contentsOf: #require(Bundle.module.url(forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures")))) }, store: store, snapURL: tmp)
    let token = "sk-ant-oat01-test-import"
    let account = try await mgr.addClaudeToken(" \n" + token + "\n", label: "Work", interval: 600)
    #expect(state.accounts.count == 1)
    #expect(account.effectiveProvider == .claude)
    #expect(account.syncInterval == 600)
    let bundle = try #require(try store.load(account.id))
    #expect(bundle.accessToken == token)
    #expect(bundle.refreshToken.isEmpty)
    #expect(!bundle.isExpiring(within: 300, now: Date()))
    #expect(!String(decoding: try Data(contentsOf: tmp), as: UTF8.self).contains(token))
}

@Test @MainActor func importClaudeToken_reauthPreservesAccountAndRejectsInvalidInput() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let (mgr, state) = makeManager(MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:], body: try Data(contentsOf: #require(Bundle.module.url(forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures")))) }, store: store, snapURL: tmp)
    let account = try await mgr.addClaudeToken("sk-ant-oat01-old", label: "Work", interval: 600)
    mgr.setPrefix(account.id, "W")
    var stale = state.accounts[0]
    stale.status = .needsReauth
    state.upsert(stale)
    try await mgr.reauthClaudeToken(account.id, token: "sk-ant-oat01-new")
    #expect(state.accounts.count == 1)
    #expect(state.accounts[0].id == account.id)
    #expect(state.accounts[0].menuBarPrefix == "W")
    #expect(state.accounts[0].syncInterval == 600)
    #expect(state.accounts[0].status == .ok)
    #expect(try store.load(account.id)?.accessToken == "sk-ant-oat01-new")
    for invalid in ["", "CODE", "sk-ant-api03-key", "sk-ant-oat01-a\nb"] {
        await #expect(throws: ClaudeTokenImportError.invalidToken) {
            try await mgr.reauthClaudeToken(account.id, token: invalid)
        }
    }
    #expect(try store.load(account.id)?.accessToken == "sk-ant-oat01-new")
}

@Test @MainActor func importClaudeToken_reauthRejectsUnknownAndCodexAccounts() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let (mgr, state) = makeManager(MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:], body: try Data(contentsOf: #require(Bundle.module.url(forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures")))) }, store: store, snapURL: tmp)
    let id = UUID()
    await #expect(throws: AccountError.unknownAccount) {
        try await mgr.reauthClaudeToken(id, token: "sk-ant-oat01-test")
    }
    state.upsert(Account(id: id, label: "Codex", accountUuid: nil, syncInterval: 300,
                         status: .never, lastSnapshot: nil, lastSyncedAt: nil, provider: .codex))
    await #expect(throws: ClaudeTokenImportError.wrongProvider) {
        try await mgr.reauthClaudeToken(id, token: "sk-ant-oat01-test")
    }
    #expect(try store.load(id) == nil)
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

@Test @MainActor func importClaudeToken_refusedUsageKeepsExistingCredentials() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { _ in HTTPResponse(status: 403, headers: [:], body: Data()) }
    let (mgr, state) = makeManager(http, store: store, snapURL: tmp)
    let id = UUID()
    let previous = TokenBundle(accessToken: "sk-ant-oat01-working", refreshToken: "RT",
                               expiresAt: .distantFuture, scopes: ["user:profile"])
    try store.save(previous, for: id)
    let account = Account(id: id, label: "Work", accountUuid: nil, syncInterval: 600,
                          status: .ok, lastSnapshot: nil, lastSyncedAt: nil)
    state.upsert(account)
    await #expect(throws: (any Error).self) {
        try await mgr.reauthClaudeToken(id, token: "sk-ant-oat01-inference-only")
    }
    #expect(try store.load(id) == previous)
    #expect(state.accounts == [account])
    #expect(!FileManager.default.fileExists(atPath: tmp.path))
}

@Test @MainActor func importClaudeToken_savesRefreshTokenOnlyAfterLiveUsageVerification() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let http = MockHTTPClient { request in
        #expect(request.url == UsageAPIClient.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-access")
        return HTTPResponse(status: 200, headers: [:], body: try Data(contentsOf:
            #require(Bundle.module.url(forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures"))))
    }
    let (manager, state) = makeManager(http, store: store, snapURL: tmp)
    let account = try await manager.addClaudeToken("sk-ant-oat01-access", refreshToken: " sk-ant-ort01-refresh ", label: "Work")
    #expect(try store.load(account.id)?.refreshToken == "sk-ant-ort01-refresh")
    #expect(account.status == .ok)
    #expect(account.lastSnapshot?.session?.utilization == 33)
    #expect(state.accounts.first == account)
    #expect(!String(decoding: try Data(contentsOf: tmp), as: UTF8.self).contains("sk-ant-"))
}

@Test(arguments: [401, 403, 429, 500]) @MainActor
func importClaudeToken_cannotCreateAccountWithoutUsageAccess(status: Int) async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let (manager, state) = makeManager(MockHTTPClient { _ in
        HTTPResponse(status: status, headers: [:], body: Data("secret-in-server-body".utf8))
    }, store: store, snapURL: tmp)
    let expected: ClaudeTokenValidationError = switch status {
    case 401: .expiredOrInvalid
    case 403: .usageRefused
    case 429: .rateLimited
    default: .temporarilyUnavailable
    }
    await #expect(throws: expected) {
        try await manager.addClaudeToken("sk-ant-oat01-access", label: "Work")
    }
    #expect(state.accounts.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: tmp.path))
}

@Test @MainActor func importClaudeToken_doesNotOverwriteRotationDuringVerification() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = InMemoryTokenStore()
    let id = UUID()
    let old = try ClaudeTokenImport.bundle(from: "sk-ant-oat01-old", refreshToken: "sk-ant-ort01-old")
    let rotated = try ClaudeTokenImport.bundle(from: "sk-ant-oat01-rotated", refreshToken: "sk-ant-ort01-rotated")
    try store.save(old, for: id)
    let http = MockHTTPClient { _ in
        try store.save(rotated, for: id)
        return HTTPResponse(status: 200, headers: [:], body: try Data(contentsOf:
            #require(Bundle.module.url(forResource: "usage_full", withExtension: "json", subdirectory: "Fixtures"))))
    }
    let (manager, state) = makeManager(http, store: store, snapURL: tmp)
    let account = Account(id: id, label: "Work", accountUuid: nil, syncInterval: 300,
                          status: .ok, lastSnapshot: nil, lastSyncedAt: nil)
    state.upsert(account)
    await #expect(throws: ClaudeTokenValidationError.credentialsChanged) {
        try await manager.reauthClaudeToken(id, token: old.accessToken, refreshToken: old.refreshToken)
    }
    #expect(try store.load(id) == rotated)
    #expect(state.accounts == [account])
}

private actor SuspendedBrowserExchange: HTTPClient {
    private let usage: Data
    private var response: CheckedContinuation<HTTPResponse, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(usage: Data) { self.usage = usage }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        if request.url == UsageAPIClient.endpoint {
            return HTTPResponse(status: 200, headers: [:], body: usage)
        }
        return await withCheckedContinuation {
            response = $0
            started?.resume(); started = nil
        }
    }
    func waitForExchange() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishExchange() {
        response?.resume(returning: HTTPResponse(status: 200, headers: [:], body: Data(
            #"{"access_token":"OLD-LOGIN","refresh_token":"OLD-LOGIN-RT","expires_in":28800}"#.utf8)))
        response = nil
    }
}

@Test(arguments: [false, true]) @MainActor
func browserReauth_doesNotOverwriteNewerImportOrResurrectDeletedAccount(removed: Bool) async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let body = try Data(contentsOf: #require(Bundle.module.url(forResource: "usage_full",
                                        withExtension: "json", subdirectory: "Fixtures")))
    let http = SuspendedBrowserExchange(usage: body)
    let store = InMemoryTokenStore()
    let (manager, state) = makeManager(http, store: store, snapURL: tmp)
    let id = UUID()
    try store.save(try ClaudeTokenImport.bundle(from: "sk-ant-oat01-initial"), for: id)
    state.upsert(Account(id: id, label: "Work", accountUuid: nil, syncInterval: 300,
                         status: .needsReauth, lastSnapshot: nil, lastSyncedAt: nil))
    let pending = manager.beginLogin()!
    let operation = Task { try await manager.reauth(id, pending, code: "CODE") }
    await http.waitForExchange()
    if removed {
        manager.remove(id)
    } else {
        try await manager.reauthClaudeToken(id, token: "sk-ant-oat01-newer-import")
    }
    let expected = state.accounts
    await http.finishExchange()
    if removed {
        await #expect(throws: AccountError.unknownAccount) { try await operation.value }
        #expect(try store.load(id) == nil)
    } else {
        await #expect(throws: ClaudeTokenValidationError.credentialsChanged) { try await operation.value }
        #expect(try store.load(id)?.accessToken == "sk-ant-oat01-newer-import")
    }
    #expect(state.accounts == expected)
}
