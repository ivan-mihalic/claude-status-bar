// Tests/ClaudeStatusBarCoreTests/EnergyPolicyTests.swift
import Testing
import Foundation
@testable import ClaudeStatusBarCore

// MARK: Adaptivní interval

@Test func adaptive_busyAccount_keepsTheBaseInterval() {
    // Nad 80 % je zbytek limitu to jediné, na čem záleží — šetřit se tady nemá.
    #expect(SyncScheduler.adaptiveMultiplier(utilization: 95) == 1)
    #expect(SyncScheduler.adaptiveMultiplier(utilization: 80) == 1)
}

@Test func adaptive_middleBand_triplesTheInterval() {
    #expect(SyncScheduler.adaptiveMultiplier(utilization: 79.9) == 3)
    #expect(SyncScheduler.adaptiveMultiplier(utilization: 20) == 3)
}

@Test func adaptive_idleAccount_sixTimesTheInterval() {
    #expect(SyncScheduler.adaptiveMultiplier(utilization: 19.9) == 6)
    #expect(SyncScheduler.adaptiveMultiplier(utilization: 0) == 6)
}

@Test func adaptive_noDataYet_doesNotSlowTheFirstSyncs() {
    // Účet bez snapshotu ještě nic neví — zpomalit ho by znamenalo, že se první
    // čísla objeví za půl hodiny.
    #expect(SyncScheduler.adaptiveMultiplier(utilization: nil) == 1)
}

@Test func nextInterval_appliesAdaptiveMultiplier() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(SyncScheduler.nextInterval(base: 300, status: .ok, consecutiveRateLimits: 0,
                                       now: now, utilization: 90) == 300)
    #expect(SyncScheduler.nextInterval(base: 300, status: .ok, consecutiveRateLimits: 0,
                                       now: now, utilization: 50) == 900)
    #expect(SyncScheduler.nextInterval(base: 300, status: .ok, consecutiveRateLimits: 0,
                                       now: now, utilization: 5) == 1800)
}

@Test func nextInterval_energyMultiplierStacksOnTopOfAdaptive() {
    let now = Date(timeIntervalSince1970: 0)
    // Klidný účet na baterii: 300 × 6 × 2 = 3600, což je zároveň strop.
    #expect(SyncScheduler.nextInterval(base: 300, status: .ok, consecutiveRateLimits: 0,
                                       now: now, utilization: 5, energyMultiplier: 2) == 3600)
}

@Test func nextInterval_isCappedSoAnAccountNeverGoesDark() {
    let now = Date(timeIntervalSince1970: 0)
    // Bez stropu by hodinový základ v Low Power Mode vyrostl na 18 hodin.
    let dt = SyncScheduler.nextInterval(base: 3600, status: .ok, consecutiveRateLimits: 0,
                                        now: now, utilization: 0, energyMultiplier: 3)
    #expect(dt == SyncScheduler.maxAdaptiveInterval)
    #expect(dt == 3600)
}

@Test func nextInterval_neverGoesBelowTheUsersOwnSetting() {
    // Násobiče interval jen prodlužují. Uživatelské nastavení je podlaha, ne cíl.
    let now = Date(timeIntervalSince1970: 0)
    for u in [nil, 0, 25, 50, 99, 100] as [Double?] {
        let dt = SyncScheduler.nextInterval(base: 600, status: .ok, consecutiveRateLimits: 0,
                                            now: now, utilization: u)
        #expect(dt >= 600)
    }
}

@Test func nextInterval_rateLimited_ignoresAdaptiveAndEnergy() {
    // Rate limit má vlastní aritmetiku; přiživit ji úsporným násobičem by znamenalo
    // čekat dlouho po tom, co limit spadl.
    let now = Date(timeIntervalSince1970: 1000)
    let dt = SyncScheduler.nextInterval(
        base: 300, status: .rateLimited(retryAt: now.addingTimeInterval(500)),
        consecutiveRateLimits: 1, now: now, utilization: 0, energyMultiplier: 3)
    #expect(dt == 500)
}

// MARK: Energetická politika

@Test func policy_onMains_changesNothing() {
    let c = EnergyConditions()
    #expect(EnergyPolicy.syncMultiplier(c) == 1)
    #expect(EnergyPolicy.syncPaused(c) == false)
    #expect(EnergyPolicy.hoverTracking(c) == true)
}

@Test func policy_battery_and_lowPower_stretchTheInterval() {
    #expect(EnergyPolicy.syncMultiplier(EnergyConditions(onBattery: true)) == 2)
    #expect(EnergyPolicy.syncMultiplier(EnergyConditions(lowPowerMode: true)) == 3)
    // Low Power Mode vyhrává nad baterií, ne aby se násobily.
    #expect(EnergyPolicy.syncMultiplier(
        EnergyConditions(lowPowerMode: true, onBattery: true)) == 3)
}

@Test func policy_screenAsleep_stopsEverythingUserFacing() {
    // Uspaná obrazovka je jediný stav, kdy se práce nedá čím obhájit: panel nikdo
    // nevidí a čísla si nikdo nepřečte.
    let c = EnergyConditions(screenAsleep: true)
    #expect(EnergyPolicy.syncPaused(c) == true)
    #expect(EnergyPolicy.hoverTracking(c) == false)
}

@Test func policy_screenAsleepBeatsEverythingElse() {
    let c = EnergyConditions(lowPowerMode: false, onBattery: false, screenAsleep: true)
    #expect(EnergyPolicy.syncPaused(c) == true)
}
