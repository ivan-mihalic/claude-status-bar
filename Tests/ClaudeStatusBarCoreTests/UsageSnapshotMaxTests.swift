// Tests/ClaudeStatusBarCoreTests/UsageSnapshotMaxTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

private func win(_ u: Double) -> UsageWindow {
    UsageWindow(key: "k", label: "l", utilization: u, resetsAt: Date(timeIntervalSince1970: 0))
}

// `allWindows` staví pokaždé nové pole. Volalo se to na každý pohyb myší (přes
// NotchModel.rings), takže tahle vlastnost existuje proto, aby se na tutéž otázku
// dalo odpovědět bez alokace.
@Test func maxUtilization_matchesTheArrayBasedAnswer() {
    let cases: [UsageSnapshot] = [
        UsageSnapshot(session: win(10), weekAll: win(20), weekPremium: [],
                      fetchedAt: Date(timeIntervalSince1970: 0)),
        UsageSnapshot(session: win(90), weekAll: win(20), weekPremium: [win(50)],
                      fetchedAt: Date(timeIntervalSince1970: 0)),
        UsageSnapshot(session: win(0), weekAll: win(0), weekPremium: [win(0), win(99.5)],
                      fetchedAt: Date(timeIntervalSince1970: 0)),
    ]
    for snap in cases {
        #expect(snap.maxUtilization == snap.allWindows.map(\.utilization).max())
    }
}
