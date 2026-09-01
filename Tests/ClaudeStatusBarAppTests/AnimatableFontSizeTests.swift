// Tests/ClaudeStatusBarAppTests/AnimatableFontSizeTests.swift
import Testing
import SwiftUI
@testable import ClaudeStatusBarApp

// Nahlášeno: písmena uprostřed prstenců jdou při rozbalování jinak než kruhy kolem nich.
// Příčina je v tom, že velikost fontu není animovatelná hodnota — tenhle modifikátor jí
// tou hodnotou dělá. Test hlídá mechanismus: kdyby se někdo vrátil k .font(.system(size:)),
// tenhle typ zmizí a test se nepřeloží.
@Test func fontSize_isAnimatableData() {
    var m = AnimatableFontSize(size: 10, weight: .bold, design: .rounded)
    #expect(m.animatableData == 10)

    // Přesně tohle dělá SwiftUI mezi snímky.
    m.animatableData = 13.8
    #expect(m.size == 13.8)
    #expect(m.weight == .bold)     // interpolace nesmí přepsat zbytek stylu
    #expect(m.design == .rounded)
}

@Test func fontSize_interpolatesToTheMidpoint() {
    var m = AnimatableFontSize(size: 7.2)
    let target: CGFloat = 13.8
    m.animatableData += (target - m.animatableData) / 2
    #expect(m.size == 10.5)
}
