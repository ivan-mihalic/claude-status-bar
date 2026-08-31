// Tests/ClaudeStatusBarAppTests/EnergyMonitorTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarApp
@testable import ClaudeStatusBarCore

@MainActor
private final class Inputs {
    var lowPower = false
    var battery = false
}

@Test @MainActor func monitor_reportsWhatItReads() {
    let inputs = Inputs()
    let m = EnergyMonitor(isLowPower: { inputs.lowPower }, isOnBattery: { inputs.battery })
    var seen: [EnergyConditions] = []
    m.onChange = { seen.append($0) }

    m.refresh()
    #expect(m.conditions == EnergyConditions())
    #expect(seen.isEmpty)          // nic se nezměnilo -> nikdo se nebudí

    inputs.battery = true
    m.refresh()
    #expect(m.conditions.onBattery == true)
    #expect(seen.count == 1)

    inputs.lowPower = true
    m.refresh()
    #expect(m.conditions == EnergyConditions(lowPowerMode: true, onBattery: true))
    #expect(seen.count == 2)
}

// Bez tohohle by každé probuzení power-source notifikace protlačilo změnu dál a
// restartovalo poll smyčku, i kdyby se stav vůbec nezměnil.
@Test @MainActor func monitor_doesNotFireWhenNothingMoved() {
    let inputs = Inputs()
    let m = EnergyMonitor(isLowPower: { inputs.lowPower }, isOnBattery: { inputs.battery })
    var fired = 0
    m.onChange = { _ in fired += 1 }

    inputs.battery = true
    m.refresh()
    #expect(fired == 1)
    m.refresh(); m.refresh(); m.refresh()
    #expect(fired == 1)
}

@Test @MainActor func monitor_screenSleepIsPartOfTheSameSnapshot() {
    let m = EnergyMonitor(isLowPower: { false }, isOnBattery: { false })
    var last: EnergyConditions?
    m.onChange = { last = $0 }

    m.setScreensAsleepForTesting(true)
    #expect(last?.screenAsleep == true)
    #expect(EnergyPolicy.syncPaused(m.conditions) == true)

    m.setScreensAsleepForTesting(false)
    #expect(last?.screenAsleep == false)
    #expect(EnergyPolicy.syncPaused(m.conditions) == false)
}
