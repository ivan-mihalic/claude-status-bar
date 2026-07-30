import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func win(_ u: Double) -> UsageWindow {
    UsageWindow(key: "k", label: "l", utilization: u, resetsAt: .init(timeIntervalSince1970: 0))
}

private func snap(_ s: Double, _ w: Double, _ p: Double) -> UsageSnapshot {
    UsageSnapshot(session: win(s), weekAll: win(w),
                  weekPremium: [win(p)], fetchedAt: .init(timeIntervalSince1970: 0))
}

@Test func effectiveInterval_appliesFloor() {
    var a = Account(id: UUID(), label: "x", accountUuid: nil,
                     syncInterval: 5, status: .never,
                     lastSnapshot: nil, lastSyncedAt: nil)
    #expect(a.effectiveInterval == 60)
    a.syncInterval = 300
    #expect(a.effectiveInterval == 300)
}

@Test func maxUtilization_acrossAccountsAndWindows() {
    let s = AppState()
    let a = Account(id: UUID(), label: "a", accountUuid: nil,
                     syncInterval: 300, status: .ok, lastSnapshot: snap(10, 20, 5),
                     lastSyncedAt: nil)
    let b = Account(id: UUID(), label: "b", accountUuid: nil,
                     syncInterval: 300, status: .ok, lastSnapshot: snap(30, 88, 40),
                     lastSyncedAt: nil)
    s.upsert(a); s.upsert(b)
    #expect(s.maxUtilization == 88)
}

@Test func upsert_replacesById_and_remove() {
    let s = AppState()
    let id = UUID()
    let a = Account(id: id, label: "a", accountUuid: nil, syncInterval: 300,
                     status: .ok, lastSnapshot: nil, lastSyncedAt: nil)
    s.upsert(a)
    var a2 = a; a2.label = "a-renamed"
    s.upsert(a2)
    #expect(s.accounts.count == 1)
    #expect(s.accounts.first?.label == "a-renamed")
    s.remove(id)
    #expect(s.accounts.isEmpty)
}

private func acct(_ label: String) -> Account {
    Account(id: UUID(), label: label, accountUuid: nil, syncInterval: 300,
            status: .ok, lastSnapshot: nil, lastSyncedAt: nil)
}

@Test func move_reordersAccounts_inBothDirections() {
    let s = AppState()
    let (a, b, c) = (acct("a"), acct("b"), acct("c"))
    [a, b, c].forEach(s.upsert)
    #expect(s.move(c.id, by: -1) == true)
    #expect(s.accounts.map(\.label) == ["a", "c", "b"])
    #expect(s.move(a.id, by: 1) == true)
    #expect(s.accounts.map(\.label) == ["c", "a", "b"])
}

@Test func move_atEdges_orUnknownID_isNoOp() {
    let s = AppState()
    let (a, b) = (acct("a"), acct("b"))
    [a, b].forEach(s.upsert)
    #expect(s.move(a.id, by: -1) == false)      // already first
    #expect(s.move(b.id, by: 1) == false)       // already last
    #expect(s.move(UUID(), by: -1) == false)    // unknown account
    #expect(s.accounts.map(\.label) == ["a", "b"])
}

@Test func upsert_afterMove_keepsPosition() {
    let s = AppState()
    let (a, b) = (acct("a"), acct("b"))
    [a, b].forEach(s.upsert)
    _ = s.move(b.id, by: -1)
    var renamed = b; renamed.label = "b2"
    s.upsert(renamed)
    #expect(s.accounts.map(\.label) == ["b2", "a"])
}

@Test func report_storesRedactedMessage_andClearResets() {
    let s = AppState()
    #expect(s.lastError == nil)
    s.report("disk write failed: sk-ant-oat01-SECRET")
    #expect(s.lastError != nil)
    #expect(!(s.lastError!.contains("SECRET")))   // redacted
    s.clearError()
    #expect(s.lastError == nil)
}
