import Testing
import Foundation
@testable import ClaudeStatusBarApp

@Test func percent_roundsToWhole() { #expect(Format.percent(33.4) == "33%") ; #expect(Format.percent(0) == "0%") }
@Test func bar_fillsProportionally() {
    #expect(Format.bar(50, width: 8) == "████░░░░")
    #expect(Format.bar(0, width: 4) == "░░░░")
    #expect(Format.bar(100, width: 4) == "████")
}
@Test func resetCountdown_formatsHoursMinutes() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(Format.resetCountdown(to: now.addingTimeInterval(2*3600 + 14*60), now: now) == "resets in 2h 14m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(45*60), now: now) == "resets in 45m")
    #expect(Format.resetCountdown(to: now.addingTimeInterval(-10), now: now) == "resetting…")
}
