// Tests/ClaudeStatusBarAppTests/RingsAtRestTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import ClaudeStatusBarApp

private let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                    topInset: 38, auxiliaryTopLeftWidth: 620)
private let plain = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 3360, height: 1859),
                                  topInset: 0, auxiliaryTopLeftWidth: nil)

// MARK: Volba podle typu displeje

@Test func ringsAtRest_picksTheFieldForTheScreenInFront() {
    let s = RingsAtRest(onNotchedDisplay: false, onPlainDisplay: true)
    #expect(s.value(hasNotch: true) == false)
    #expect(s.value(hasNotch: false) == true)
}

// Přesně Ivanův případ: na samotném MacBooku schované, s připojeným monitorem
// zobrazené — a nic se nepřepíná ručně.
@Test func layout_readsTheSettingThatMatchesTheDisplay() {
    let setting = RingsAtRest(onNotchedDisplay: false, onPlainDisplay: true)

    let onNotched = NotchGeometry.layout(for: notched, placement: .topCenter,
                                         ringCount: 3, ringsAtRest: setting)
    let onPlain = NotchGeometry.layout(for: plain, placement: .topCenter,
                                       ringCount: 3, ringsAtRest: setting)
    #expect(onNotched.showsRingsAtRest == false)
    #expect(onPlain.showsRingsAtRest == true)

    // A není to jen příznak: panel v klidu má na každém z nich jinou velikost.
    #expect(onNotched.collapsed.size != onPlain.collapsed.size)
}

@Test func layout_theOtherWayRoundToo() {
    let setting = RingsAtRest(onNotchedDisplay: true, onPlainDisplay: false)
    #expect(NotchGeometry.layout(for: notched, placement: .topCenter,
                                 ringCount: 3, ringsAtRest: setting).showsRingsAtRest == true)
    #expect(NotchGeometry.layout(for: plain, placement: .topCenter,
                                 ringCount: 3, ringsAtRest: setting).showsRingsAtRest == false)
}

// Na hraně není kam se schovat, takže prstence jsou vidět vždycky a nastavení se jich netýká.
@Test func edgePlacements_ignoreTheSettingEntirely() {
    for placement in [NotchPlacement.leftEdge, .rightEdge] {
        for setting in [RingsAtRest(onNotchedDisplay: false, onPlainDisplay: false),
                        RingsAtRest(onNotchedDisplay: true, onPlainDisplay: true)] {
            for screen in [notched, plain] {
                #expect(NotchGeometry.layout(for: screen, placement: placement,
                                             ringCount: 3, ringsAtRest: setting)
                            .showsRingsAtRest == true)
            }
        }
    }
}

// MARK: Přechod z jediného přepínače na dva

@Test func migration_carriesTheOldValueIntoBothDisplays() {
    #expect(NotchSettingsMigration.migrate(legacy: true, notched: nil, plain: nil)?.notched == true)
    #expect(NotchSettingsMigration.migrate(legacy: true, notched: nil, plain: nil)?.plain == true)
    #expect(NotchSettingsMigration.migrate(legacy: false, notched: nil, plain: nil)?.notched == false)
}

@Test func migration_doesNothingWithoutAnOldValue() {
    #expect(NotchSettingsMigration.migrate(legacy: nil, notched: nil, plain: nil) == nil)
}

// Jednou a dost: druhý běh nesmí přepsat to, co si mezitím uživatel nastavil.
@Test func migration_neverClobbersASettingThatAlreadyExists() {
    #expect(NotchSettingsMigration.migrate(legacy: true, notched: false, plain: nil) == nil)
    #expect(NotchSettingsMigration.migrate(legacy: true, notched: nil, plain: false) == nil)
    #expect(NotchSettingsMigration.migrate(legacy: true, notched: true, plain: true) == nil)
}

@Test func migration_appliedToRealDefaults_movesTheValueAndRemovesTheOldKey() {
    let suite = "csb-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(true, forKey: NotchSettingsMigration.legacyKey)
    NotchSettingsMigration.apply(to: defaults)

    #expect(defaults.bool(forKey: NotchSettingsMigration.notchedKey) == true)
    #expect(defaults.bool(forKey: NotchSettingsMigration.plainKey) == true)
    #expect(defaults.object(forKey: NotchSettingsMigration.legacyKey) == nil)
}
