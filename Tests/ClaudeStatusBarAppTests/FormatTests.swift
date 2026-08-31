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
@Test func relativeSync_minutesFirst() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(Format.relativeSync(from: nil, now: now) == "Never synced")
    #expect(Format.relativeSync(from: now.addingTimeInterval(-2), now: now) == "Synced just now")
    #expect(Format.relativeSync(from: now.addingTimeInterval(-30), now: now) == "Synced 30s ago")
    #expect(Format.relativeSync(from: now.addingTimeInterval(-5*60), now: now) == "Synced 5 min ago")
    #expect(Format.relativeSync(from: now.addingTimeInterval(-3*3600), now: now) == "Synced 3h ago")
    #expect(Format.relativeSync(from: now.addingTimeInterval(-2*86400), now: now) == "Synced 2d ago")
}

// MARK: Last-sync stamp for the notch popover

private let prague = TimeZone(identifier: "Europe/Prague")!
private let noon = Date(timeIntervalSince1970: 1_788_177_600)   // 2026-08-31 12:00 UTC

@Test func lastSync_readsAsAnAgeWithinADay() {
    #expect(Format.lastSync(noon, now: noon, timeZone: prague) == "just now")
    #expect(Format.lastSync(noon.addingTimeInterval(-30), now: noon, timeZone: prague) == "30s ago")
    #expect(Format.lastSync(noon.addingTimeInterval(-5 * 60), now: noon, timeZone: prague) == "5 min ago")
    #expect(Format.lastSync(noon.addingTimeInterval(-3 * 3600), now: noon, timeZone: prague) == "3h ago")
}

@Test func lastSync_switchesToAnAbsoluteStampAfterADay() {
    // Past a day "27h ago" stops meaning anything; a date does.
    let old = noon.addingTimeInterval(-27 * 3600)
    let text = Format.lastSync(old, now: noon, timeZone: prague)
    #expect(!text.contains("ago"))
    #expect(text.contains(":"))
}

@Test func lastSync_boundaryIsExactlyTwentyFourHours() {
    // The seam is where a silent off-by-one hides: at 24h it must already be a date.
    let justUnder = noon.addingTimeInterval(-(24 * 3600 - 1))
    let atLimit = noon.addingTimeInterval(-24 * 3600)
    #expect(Format.lastSync(justUnder, now: noon, timeZone: prague).hasSuffix("ago"))
    #expect(!Format.lastSync(atLimit, now: noon, timeZone: prague).hasSuffix("ago"))
}

@Test func lastSync_absoluteStampIsInTheGivenZone_notTheMachines() {
    // 12:00 UTC is 14:00 in Prague (CEST). Reading the machine's zone instead would make
    // the stamp mean something different on a travelling laptop.
    let old = noon.addingTimeInterval(-48 * 3600)
    let inPrague = Format.lastSync(old, now: noon, timeZone: prague)
    let inUTC = Format.lastSync(old, now: noon, timeZone: TimeZone(identifier: "UTC")!)
    #expect(inPrague.contains("14:00"))
    #expect(inUTC.contains("12:00"))
    #expect(inPrague != inUTC)
}

@Test func lastSync_neverSyncedSaysSo() {
    #expect(Format.lastSync(nil, now: noon, timeZone: prague) == "Never")
}

@Test func lastSync_aClockThatWentBackwardsDoesNotPrintNegativeAges() {
    // Snapshots restored after a clock change can be "in the future"; "-3h ago" reads as a bug.
    #expect(Format.lastSync(noon.addingTimeInterval(120), now: noon, timeZone: prague) == "just now")
}
