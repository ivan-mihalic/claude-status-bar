import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private func window(_ u: Double) -> UsageWindow {
    UsageWindow(key: "five_hour", label: "Current session", utilization: u,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
}
private func account(status: AccountStatus, snapshot: UsageSnapshot?) -> Account {
    Account(id: UUID(), label: "work", accountUuid: nil, syncInterval: 300,
            status: status, lastSnapshot: snapshot, lastSyncedAt: nil)
}
private let snapshot = UsageSnapshot(session: window(41), weekAll: window(60),
                                     weekPremium: [],
                                     fetchedAt: Date(timeIntervalSince1970: 1_799_000_000))

@Test func ring_showsTheWorstWindow() {
    let r = NotchModel.ring(for: account(status: .ok, snapshot: snapshot))
    #expect(r.percent == 60)
    #expect(r.level == .ok)
    #expect(r.badge == nil)
    #expect(r.label == "work")
}

@Test func ring_hasNoPercentWithoutASnapshot() {
    let r = NotchModel.ring(for: account(status: .never, snapshot: nil))
    #expect(r.percent == nil)
    #expect(r.level == .unknown)
    #expect(r.badge == .syncing)
}

// The point of this test: a surface that can only render a number will happily show a
// stale 60% while the token is dead. Every non-ok status must reach the ring.
@Test func everyFailureStatus_reachesTheRing() {
    #expect(NotchModel.ring(for: account(status: .offline, snapshot: snapshot)).badge == .offline)
    #expect(NotchModel.ring(for: account(status: .needsReauth, snapshot: snapshot)).badge == .signIn)
    #expect(NotchModel.ring(for: account(status: .rateLimited(retryAt: Date()),
                                         snapshot: snapshot)).badge == .rateLimited)
    #expect(NotchModel.ring(for: account(status: .never, snapshot: snapshot)).badge == .syncing)
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot)).badge == nil)
}

@Test func failingAccount_keepsItsLastKnownPercent() {
    // Showing the last number is fine — showing it *without* the badge is not.
    let r = NotchModel.ring(for: account(status: .offline, snapshot: snapshot))
    #expect(r.percent == 60)
    #expect(r.badge == .offline)
}

@Test func rings_preserveAccountOrder() {
    let a = account(status: .ok, snapshot: snapshot)
    let b = account(status: .ok, snapshot: snapshot)
    #expect(NotchModel.rings(accounts: [a, b]).map(\.id) == [a.id, b.id])
}
