// Tests/ClaudeStatusBarAppTests/EnergySyncTests.swift
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

private func snapshot(max utilization: Double) -> UsageSnapshot {
    let reset = Date(timeIntervalSince1970: 10_000)
    return UsageSnapshot(
        session: UsageWindow(key: "five_hour", label: "Session",
                             utilization: utilization, resetsAt: reset),
        weekAll: UsageWindow(key: "seven_day", label: "Week",
                             utilization: 0, resetsAt: reset),
        weekPremium: [], fetchedAt: Date(timeIntervalSince1970: 0))
}

@MainActor
private func account(_ id: UUID, utilization: Double?) -> Account {
    Account(id: id, label: "a", accountUuid: nil, syncInterval: 300, status: .ok,
            lastSnapshot: utilization.map { snapshot(max: $0) },
            lastSyncedAt: Date(timeIntervalSince1970: 0))
}

@MainActor
private func fixture(_ utilization: Double?) -> (SyncCoordinator, UUID, AppState, URL) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("csb-\(UUID()).json")
    let clock = ManualClock(Date(timeIntervalSince1970: 0))
    let state = AppState()
    let id = UUID()
    state.upsert(account(id, utilization: utilization))
    let http = MockHTTPClient { _ in HTTPResponse(status: 200, headers: [:], body: Data()) }
    return (coord(http, state, InMemoryTokenStore(), clock, tmp), id, state, tmp)
}

// MARK: Adaptivní interval na úrovni koordinátoru

@Test @MainActor func nextDelay_busyAccount_keepsTheUsersInterval() {
    let (c, id, _, tmp) = fixture(92)
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(c.nextDelay(for: id, now: Date(timeIntervalSince1970: 0)) == 300)
}

@Test @MainActor func nextDelay_quietAccount_stretchesToSixTimesTheInterval() {
    let (c, id, _, tmp) = fixture(4)
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(c.nextDelay(for: id, now: Date(timeIntervalSince1970: 0)) == 1800)
}

@Test @MainActor func nextDelay_neverSynced_doesNotWaitHalfAnHourForFirstNumbers() {
    let (c, id, _, tmp) = fixture(nil)
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(c.nextDelay(for: id, now: Date(timeIntervalSince1970: 0)) == 300)
}

@Test @MainActor func nextDelay_onBattery_stretchesFurtherThanOnMains() {
    let (c, id, _, tmp) = fixture(50)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 0)
    #expect(c.nextDelay(for: id, now: now) == 900)          // 300 × 3
    c.updateConditions(EnergyConditions(onBattery: true))
    #expect(c.nextDelay(for: id, now: now) == 1800)         // × 2 navíc
}

// MARK: Uspaná obrazovka

@Test @MainActor func screenAsleep_stopsTheLoopEntirely() async {
    let (c, _, _, tmp) = fixture(50)
    defer { try? FileManager.default.removeItem(at: tmp) }
    defer { c.stop() }

    c.start()
    #expect(c.isRunning == true)
    c.updateConditions(EnergyConditions(screenAsleep: true))
    #expect(c.isRunning == false)
}

@Test @MainActor func screenWake_startsTheLoopAgain() async {
    let (c, _, _, tmp) = fixture(50)
    defer { try? FileManager.default.removeItem(at: tmp) }
    defer { c.stop() }

    c.start()
    c.updateConditions(EnergyConditions(screenAsleep: true))
    #expect(c.isRunning == false)
    c.updateConditions(EnergyConditions())
    // Probuzení nesmí jen znovu nastartovat časovač — musí to být sync hned, jinak
    // se po noci kouká uživatel na čísla stará osm hodin.
    #expect(c.isRunning == true)
}

@Test @MainActor func conditionsThatDoNotChangeAnything_doNotRestartTheLoop() async {
    let (c, _, _, tmp) = fixture(50)
    defer { try? FileManager.default.removeItem(at: tmp) }
    defer { c.stop() }

    c.start()
    let before = c.isRunning
    c.updateConditions(EnergyConditions())   // stejné jako výchozí stav
    #expect(c.isRunning == before)
}
