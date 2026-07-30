import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

private func acct() -> Account {
    Account(id: UUID(), label: "a@x", accountUuid: nil, syncInterval: 300,
            status: .never, lastSnapshot: nil, lastSyncedAt: nil)
}
private func snap(_ s: Double) -> UsageSnapshot {
    let w = UsageWindow(key: "five_hour", label: "Session", utilization: s, resetsAt: Date(timeIntervalSince1970: 0))
    return UsageSnapshot(session: w, weekAll: w, weekPremium: [], fetchedAt: Date(timeIntervalSince1970: 0))
}

@Test func reduce_success_setsOkAndSnapshot() {
    let now = Date(timeIntervalSince1970: 1000)
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 3),
                                 outcome: .success(snap(42)), now: now, backoff: .usage)
    #expect(out.account.status == .ok)
    #expect(out.account.lastSnapshot?.session.utilization == 42)
    #expect(out.account.lastSyncedAt == now)
    #expect(out.consecutiveRateLimits == 0)
}
@Test func reduce_rateLimited_incrementsAndSetsRetryAt() {
    let now = Date(timeIntervalSince1970: 1000)
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 0),
                                 outcome: .rateLimited(retryAfter: nil), now: now, backoff: .usage)
    #expect(out.consecutiveRateLimits == 1)
    #expect(out.account.status == .rateLimited(retryAt: now.addingTimeInterval(30)))
}

@Test func reduce_rateLimited_prefersServerRetryAfterOverBackoff() {
    let now = Date(timeIntervalSince1970: 1000)
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 0),
                                 outcome: .rateLimited(retryAfter: 900), now: now, backoff: .usage)
    #expect(out.account.status == .rateLimited(retryAt: now.addingTimeInterval(900)))
}

/// With no Retry-After header, the app already knows when the limit lifts — the last
/// snapshot carries each window's reset time. Waiting for the exhausted window's reset
/// beats a 30s backoff that just re-hits the limit hundreds of times.
@Test func reduce_rateLimited_withoutHeader_waitsForTheExhaustedWindowReset() {
    let now = Date(timeIntervalSince1970: 1000)
    let maxed = UsageWindow(key: "seven_day", label: "Week (all)", utilization: 100,
                            resetsAt: Date(timeIntervalSince1970: 9000))
    let fresh = UsageWindow(key: "five_hour", label: "Session", utilization: 10,
                            resetsAt: Date(timeIntervalSince1970: 2000))
    let account = Account(id: UUID(), label: "a@x", accountUuid: nil, syncInterval: 300,
                          status: .ok,
                          lastSnapshot: UsageSnapshot(session: fresh, weekAll: maxed,
                                                      weekPremium: [], fetchedAt: now),
                          lastSyncedAt: now)
    let out = SyncReducer.reduce(SyncState(account: account, consecutiveRateLimits: 0),
                                 outcome: .rateLimited(retryAfter: nil), now: now, backoff: .usage)
    #expect(out.account.status == .rateLimited(retryAt: Date(timeIntervalSince1970: 9000)))
}
@Test func reduce_needsReauth_resetsCounter() {
    let out = SyncReducer.reduce(SyncState(account: acct(), consecutiveRateLimits: 4),
                                 outcome: .needsReauth, now: Date(timeIntervalSince1970: 0), backoff: .usage)
    #expect(out.account.status == .needsReauth)
    #expect(out.consecutiveRateLimits == 0)
}
@Test func reduce_offline_keepsSnapshotAndResetsCounter() {
    let account = Account(id: UUID(), label: "a@x", accountUuid: nil, syncInterval: 300,
                           status: .never, lastSnapshot: snap(50), lastSyncedAt: nil)
    let out = SyncReducer.reduce(SyncState(account: account, consecutiveRateLimits: 4),
                                 outcome: .offline, now: Date(timeIntervalSince1970: 0), backoff: .usage)
    #expect(out.account.status == .offline)
    #expect(out.account.lastSnapshot?.session.utilization == 50)
    #expect(out.consecutiveRateLimits == 0)
}
@Test func reduce_failed_setsOfflineAndKeepsSnapshot() {
    let account = Account(id: UUID(), label: "a@x", accountUuid: nil, syncInterval: 300,
                           status: .never, lastSnapshot: snap(50), lastSyncedAt: nil)
    let out = SyncReducer.reduce(SyncState(account: account, consecutiveRateLimits: 4),
                                 outcome: .failed("decoding"), now: Date(timeIntervalSince1970: 0), backoff: .usage)
    #expect(out.account.status == .offline)
    #expect(out.account.lastSnapshot?.session.utilization == 50)
}
@Test func reduce_rateLimited_keepsSnapshot() {
    let account = Account(id: UUID(), label: "a@x", accountUuid: nil, syncInterval: 300,
                           status: .never, lastSnapshot: snap(50), lastSyncedAt: nil)
    let out = SyncReducer.reduce(SyncState(account: account, consecutiveRateLimits: 0),
                                 outcome: .rateLimited(retryAfter: nil), now: Date(timeIntervalSince1970: 1000), backoff: .usage)
    #expect(out.account.lastSnapshot?.session.utilization == 50)
    #expect(out.consecutiveRateLimits == 1)
}
