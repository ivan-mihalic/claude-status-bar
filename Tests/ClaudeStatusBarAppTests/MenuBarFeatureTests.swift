import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@Test func resetCountdown_showsDaysForLongDurations() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(Format.resetCountdown(to: now.addingTimeInterval(135 * 3600), now: now) == "resets in 5d 15h 0m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(26 * 3600 + 30 * 60), now: now) == "resets in 1d 2h 30m")
    // < 24h unchanged (existing behavior preserved)
    #expect(Format.resetCountdown(to: now.addingTimeInterval(2 * 3600 + 14 * 60), now: now) == "resets in 2h 14m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(45 * 60), now: now) == "resets in 45m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(-10), now: now) == "resetting…")
}

@Test func absoluteReset_formatsDayDateTime() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var c = DateComponents()
    c.year = 2026; c.month = 7; c.day = 23; c.hour = 0; c.minute = 59
    let date = cal.date(from: c)!
    let s = Format.absoluteReset(date, locale: Locale(identifier: "en_US_POSIX"),
                                 timeZone: TimeZone(identifier: "UTC")!)
    #expect(s == "Thu 23.7. 00:59")
}

private func mkAccount(prefix: String?, session: Double?, week: Double?, premium: Double?) -> Account {
    func w(_ u: Double) -> UsageWindow {
        UsageWindow(key: "k", label: "l", utilization: u, resetsAt: Date(timeIntervalSince1970: 0))
    }
    let snap: UsageSnapshot? = session.map { s in
        UsageSnapshot(session: w(s), weekAll: w(week ?? 0),
                      weekPremium: premium.map { [w($0)] } ?? [],
                      fetchedAt: Date(timeIntervalSince1970: 0))
    }
    return Account(id: UUID(), label: "x", accountUuid: nil, syncInterval: 300,
                   status: .ok, lastSnapshot: snap, lastSyncedAt: nil, menuBarPrefix: prefix)
}

@Test func menuBarLabel_off_showsOverallMax() {
    let a = mkAccount(prefix: "W", session: 20, week: 19, premium: 5)
    let b = mkAccount(prefix: "P", session: 30, week: 88, premium: 40)
    #expect(MenuBarLabel.text(accounts: [a, b], showAccountPercents: false) == "88%")
    #expect(MenuBarLabel.text(accounts: [], showAccountPercents: false) == "—")
}

@Test func menuBarLabel_on_perAccountWithPrefix_and3Windows() {
    let a = mkAccount(prefix: "W", session: 20, week: 19, premium: 5)
    let b = mkAccount(prefix: "P", session: 30, week: 40, premium: nil) // no premium window
    #expect(MenuBarLabel.text(accounts: [a, b], showAccountPercents: true) == "W 20/19/5  P 30/40")
}

@Test func menuBarLabel_on_handlesNoPrefixAndNoData() {
    let a = mkAccount(prefix: nil, session: 20, week: 19, premium: nil)
    let noData = Account(id: UUID(), label: "x", accountUuid: nil, syncInterval: 300,
                         status: .never, lastSnapshot: nil, lastSyncedAt: nil)
    #expect(MenuBarLabel.text(accounts: [a, noData], showAccountPercents: true) == "20/19  …")
}

// MARK: Hiding accounts from the menu bar

private func mkVisible(_ prefix: String, _ pct: Double, shownInMenuBar: Bool? = nil) -> Account {
    var a = mkAccount(prefix: prefix, session: pct, week: pct, premium: nil)
    a.showInMenuBar = shownInMenuBar
    return a
}

@Test func hiddenAccounts_dropOutOfThePerAccountLabel() {
    let shown = mkVisible("W", 20)
    let hidden = mkVisible("P", 30, shownInMenuBar: false)
    let text = MenuBarLabel.text(accounts: [shown, hidden], showAccountPercents: true)
    #expect(text.contains("W"))
    #expect(!text.contains("P"))
}

@Test func accountsSavedBeforeTheSetting_stayInTheMenuBar() {
    // `nil` must mean visible: adding a switch may not silently blank someone's menu bar.
    let legacy = mkVisible("W", 20)
    #expect(legacy.showInMenuBar == nil)
    #expect(legacy.isShownInMenuBar)
    #expect(MenuBarLabel.text(accounts: [legacy], showAccountPercents: true).contains("W"))
}

@Test func aHiddenAccountStillDrivesTheWarningIcon() {
    // Hiding is about menu-bar width, not about muting an account. If a hidden account were
    // dropped from the maximum, the app would quietly stop warning about it.
    let shown = mkVisible("W", 10)
    let hidden = mkVisible("P", 95, shownInMenuBar: false)
    #expect(MenuBarLabel.text(accounts: [shown, hidden], showAccountPercents: false) == "95%")
}

@Test func hidingEveryAccount_fallsBackToTheOverallNumber() {
    // An empty label next to the icon reads as a broken app; the single worst number does not.
    let a = mkVisible("W", 20, shownInMenuBar: false)
    let b = mkVisible("P", 40, shownInMenuBar: false)
    #expect(MenuBarLabel.text(accounts: [a, b], showAccountPercents: true) == "40%")
}
