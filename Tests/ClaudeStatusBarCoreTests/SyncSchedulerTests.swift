import Testing
import Foundation
@testable import ClaudeStatusBarCore

@Test func test_stagger_spreadsAccounts() {
    #expect(SyncScheduler.staggerOffset(index: 0, spacing: 7) == 0)
    #expect(SyncScheduler.staggerOffset(index: 3, spacing: 7) == 21)
}

@Test func test_nextInterval_normal_usesBase() {
    let dt = SyncScheduler.nextInterval(
        base: 300, status: .ok, consecutiveRateLimits: 0,
        now: .init(timeIntervalSince1970: 0))
    #expect(dt == 300)
}

@Test func test_nextInterval_rateLimited_honorsRetryAtOrBackoff() {
    let now = Date(timeIntervalSince1970: 1000)
    // retryAt is 500s out -> use it (bigger than backoff for 1 failure=30)
    let dt = SyncScheduler.nextInterval(
        base: 300,
        status: .rateLimited(retryAt: now.addingTimeInterval(500)),
        consecutiveRateLimits: 1, now: now)
    #expect(dt == 500)
}

@Test func test_nextInterval_rateLimited_backoffWinsWhenRetryPassed() {
    let now = Date(timeIntervalSince1970: 1000)
    // retryAt already passed -> fall back to backoff for 3 failures = 120
    let dt = SyncScheduler.nextInterval(
        base: 300,
        status: .rateLimited(retryAt: now.addingTimeInterval(-10)),
        consecutiveRateLimits: 3, now: now)
    #expect(dt == 120)
}
