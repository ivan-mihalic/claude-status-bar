// Tests/ClaudeStatusBarAppTests/SyncAttemptTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private func account(_ status: AccountStatus, lastSyncedAt: Date?) -> Account {
    Account(id: UUID(), label: "a", accountUuid: nil, syncInterval: 300, status: status,
            lastSnapshot: nil, lastSyncedAt: lastSyncedAt)
}

// Nahlášená vada: účet je offline, uživatel zmáčkne ⟳ a NIC se nestane. Sync přitom
// proběhne — jenže při neúspěchu se nesahá na lastSyncedAt, takže se na obrazovce nezmění
// jediný znak a tlačítko vypadá jako mrtvé. Potřebuje to razítko o pokusu.
@Test func reduce_recordsTheAttempt_evenWhenItFailed() {
    let then = Date(timeIntervalSince1970: 1000)
    let now = Date(timeIntervalSince1970: 5000)
    for outcome: SyncOutcome in [.offline, .needsReauth, .failed("x"),
                                 .rateLimited(retryAfter: nil)] {
        let before = account(.ok, lastSyncedAt: then)
        let after = SyncReducer.reduce(SyncState(account: before, consecutiveRateLimits: 0),
                                       outcome: outcome, now: now).account
        #expect(after.lastAttemptAt == now, "\(outcome): pokus se nezaznamenal")
        #expect(after.lastSyncedAt == then, "\(outcome): neúspěch nesmí tvářit jako sync")
    }
}

@Test func reduce_success_stampsBothTimes() {
    let now = Date(timeIntervalSince1970: 5000)
    let snap = UsageSnapshot(
        session: UsageWindow(key: "s", label: "s", utilization: 1, resetsAt: now),
        weekAll: UsageWindow(key: "w", label: "w", utilization: 1, resetsAt: now),
        weekPremium: [], fetchedAt: now)
    let before = account(.offline, lastSyncedAt: Date(timeIntervalSince1970: 1000))
    let after = SyncReducer.reduce(SyncState(account: before, consecutiveRateLimits: 0),
                                   outcome: .success(snap), now: now).account
    #expect(after.lastSyncedAt == now)
    #expect(after.lastAttemptAt == now)
    #expect(after.status == .ok)
}

// Na tom rozdílu stojí celé hlášení v UI: „zkusil jsem to a nepovedlo se".
@Test func lastAttemptNewerThanLastSync_meansTheLastTryFailed() {
    var a = account(.offline, lastSyncedAt: Date(timeIntervalSince1970: 1000))
    a.lastAttemptAt = Date(timeIntervalSince1970: 5000)
    #expect(a.lastAttemptFailed == true)

    var b = account(.ok, lastSyncedAt: Date(timeIntervalSince1970: 5000))
    b.lastAttemptAt = Date(timeIntervalSince1970: 5000)
    #expect(b.lastAttemptFailed == false)

    // Účet, který se ještě nikdy nepokusil, nic nehlásí.
    let c = account(.never, lastSyncedAt: nil)
    #expect(c.lastAttemptFailed == false)
}

// Starý soubor s účty pole nezná — musí se dál načíst.
@Test func account_decodesWithoutTheNewField() throws {
    let json = """
    [{"id":"\(UUID().uuidString)","label":"a","syncInterval":300,
      "status":{"ok":{}}}]
    """.data(using: .utf8)!
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let accounts = try d.decode([Account].self, from: json)
    #expect(accounts.count == 1)
    #expect(accounts[0].lastAttemptAt == nil)
}

// MARK: Ruční sync

import TestSupport

@MainActor
private func offlineFixture() -> (SyncCoordinator, UUID, AppState, MockHTTPClient, URL) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    let clock = ManualClock(Date(timeIntervalSince1970: 5000))
    let store = InMemoryTokenStore()
    let id = UUID()
    try? store.save(TokenBundle(accessToken: "AT", refreshToken: "RT",
                                expiresAt: Date(timeIntervalSince1970: 1_000_000), scopes: []),
                    for: id)
    let state = AppState()
    state.upsert(Account(id: id, label: "Alfred", accountUuid: nil, syncInterval: 300,
                         status: .offline, lastSnapshot: nil,
                         lastSyncedAt: Date(timeIntervalSince1970: 1000)))
    // Síť je dole — přesně stav, ve kterém uživatel mačká ⟳.
    let http = MockHTTPClient { _ in throw URLError(.notConnectedToInternet) }
    let c = SyncCoordinator(
        appState: state,
        engine: AccountSyncEngine(
            tokenStore: store,
            oauth: OAuthClient(http: http, endpoints: .production, config: .claudeCode, clock: clock),
            usage: UsageAPIClient(http: http), clock: clock),
        clock: clock, snapshotStore: SnapshotStore(fileURL: tmp))
    return (c, id, state, http, tmp)
}

// Ověření, o které Ivan žádal: opravdu se to pokusí, tlačítko není mrtvé.
@Test @MainActor func manualSync_onAnOfflineAccount_reallyReachesTheNetwork() async {
    let (c, id, state, http, tmp) = offlineFixture()
    defer { try? FileManager.default.removeItem(at: tmp) }

    #expect(http.requests.isEmpty)
    await c.syncNow(id, manual: true)
    #expect(http.requests.isEmpty == false)          // request odešel
    #expect(state.accounts.first?.status == .offline) // a poctivě selhal
}

// A hlavně: musí to být VIDĚT. Bez razítka o pokusu se na obrazovce nezmění jediný znak.
@Test @MainActor func manualSync_thatFails_leavesAVisibleTrace() async {
    let (c, id, state, _, tmp) = offlineFixture()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let syncedBefore = state.accounts.first?.lastSyncedAt

    await c.syncNow(id, manual: true)

    let a = state.accounts.first!
    #expect(a.lastSyncedAt == syncedBefore)   // neúspěch se netváří jako sync
    #expect(a.lastAttemptFailed == true)      // ale stopa po pokusu tam je
    #expect(state.lastError != nil)           // a uživateli se to řekne
}

// Poll smyčka běží sama od sebe a spadlá síť není událost, kterou by měl kdokoli číst
// každých pár minut — hlásí se jen to, co si uživatel vyžádal.
@Test @MainActor func backgroundSync_thatFails_staysQuiet() async {
    let (c, id, state, _, tmp) = offlineFixture()
    defer { try? FileManager.default.removeItem(at: tmp) }

    await c.syncNow(id)
    #expect(state.accounts.first?.lastAttemptFailed == true)
    #expect(state.lastError == nil)
}
