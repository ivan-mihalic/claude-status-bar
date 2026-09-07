import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private func window(_ u: Double, key: String = "five_hour",
                    label: String = "Current session") -> UsageWindow {
    UsageWindow(key: key, label: label, utilization: u,
                resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
}
private func account(status: AccountStatus, snapshot: UsageSnapshot?,
                     prefix: String? = nil) -> Account {
    Account(id: UUID(), label: "work", accountUuid: nil, syncInterval: 300,
            status: status, lastSnapshot: snapshot, lastSyncedAt: nil,
            menuBarPrefix: prefix)
}
private let snapshot = UsageSnapshot(
    session: window(41),
    weekAll: window(60, key: "seven_day", label: "All models"),
    weekPremium: [window(73, key: "seven_day_opus", label: "Opus")],
    fetchedAt: Date(timeIntervalSince1970: 1_799_000_000))

@Test func rings_showTwoDifferentNumbers() {
    // Outer = worst weekly (Opus 73 beats All models 60), inner = the session.
    // If both rings drew the same value the second one would say nothing.
    let r = NotchModel.ring(for: account(status: .ok, snapshot: snapshot))
    #expect(r.weekPercent == 73)
    #expect(r.sessionPercent == 41)
    #expect(r.level == .warn)          // worst overall is 73 → warn, like the menu bar
    #expect(r.badge == nil)
    #expect(r.label == "work")
}

@Test func popoverGetsEveryWindow() {
    let r = NotchModel.ring(for: account(status: .ok, snapshot: snapshot))
    #expect(r.windows.map(\.key) == ["five_hour", "seven_day", "seven_day_opus"])
}

@Test func prefix_isUsedWhenSetAndIgnoredWhenBlank() {
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot, prefix: "W")).prefix == "W")
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot, prefix: "  ")).prefix == nil)
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot)).prefix == nil)
}

@Test func ring_hasNoPercentWithoutASnapshot() {
    let r = NotchModel.ring(for: account(status: .never, snapshot: nil))
    #expect(r.weekPercent == nil)
    #expect(r.sessionPercent == nil)
    #expect(r.windows.isEmpty)
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
    // Showing the last numbers is fine — showing them *without* the badge is not.
    let r = NotchModel.ring(for: account(status: .offline, snapshot: snapshot))
    #expect(r.weekPercent == 73)
    #expect(r.sessionPercent == 41)
    #expect(r.badge == .offline)
}

@Test func rings_preserveAccountOrder() {
    let a = account(status: .ok, snapshot: snapshot)
    let b = account(status: .ok, snapshot: snapshot)
    #expect(NotchModel.rings(accounts: [a, b]).map(\.id) == [a.id, b.id])
}

// MARK: Per-account visibility

@Test func hiddenAccounts_getNoRing() {
    var hidden = account(status: .ok, snapshot: snapshot)
    hidden.showInNotch = false
    let shown = account(status: .ok, snapshot: snapshot)
    #expect(NotchModel.rings(accounts: [hidden, shown]).map(\.id) == [shown.id])
}

@Test func accountsSavedBeforeThePanelExisted_areShown() {
    // `nil` must mean visible: turning a feature on may not silently hide someone's account.
    let legacy = account(status: .ok, snapshot: snapshot)
    #expect(legacy.showInNotch == nil)
    #expect(legacy.isShownInNotch)
    #expect(NotchModel.rings(accounts: [legacy]).count == 1)
}

@Test func hidingEveryAccount_leavesAnEmptyPanelRatherThanACrash() {
    var a = account(status: .ok, snapshot: snapshot); a.showInNotch = false
    var b = account(status: .ok, snapshot: snapshot); b.showInNotch = false
    #expect(NotchModel.rings(accounts: [a, b]).isEmpty)
}

@Test func ringCarriesItsProvider() {
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot)).provider == .claude)
    var codex = account(status: .ok, snapshot: snapshot)
    codex.provider = .codex
    #expect(NotchModel.ring(for: codex).provider == .codex)
}

@Test func ringCarriesTheAccountsSelectedColour() {
    var coloured = account(status: .ok, snapshot: snapshot)
    coloured.ringColor = AccountRingColor(red: 0.1, green: 0.2, blue: 0.3)
    #expect(NotchModel.ring(for: coloured).ringColor == coloured.ringColor)
    #expect(NotchModel.ring(for: account(status: .ok, snapshot: snapshot)).ringColor == nil)
}

@Test func weeklyOnlyCodexUsage_fillsTheOuterRingWithoutInventingASession() {
    let weekly = window(27, key: "seven_day", label: "Week")
    var codex = account(status: .ok,
        snapshot: UsageSnapshot(session: nil, weekAll: weekly,
                                weekPremium: [], fetchedAt: Date()))
    codex.provider = .codex

    let ring = NotchModel.ring(for: codex)
    #expect(ring.weekPercent == 27)
    #expect(ring.sessionPercent == nil)
    #expect(ring.windows == [weekly])
}
