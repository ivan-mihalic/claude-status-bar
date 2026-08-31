import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

/// A notched built-in display sitting at the global origin.
private let builtInPrimary = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                                           topInset: 38, auxiliaryTopLeftWidth: 727)
/// The same built-in panel, but the user made the external display primary, so it no longer
/// sits at the origin.
private let builtInSecondary = ScreenMetrics(frame: CGRect(x: -1710, y: 0, width: 1710, height: 1107),
                                             topInset: 38, auxiliaryTopLeftWidth: 727)
private let externalPrimary = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                            topInset: 0, auxiliaryTopLeftWidth: nil)
private let externalSecondary = ScreenMetrics(frame: CGRect(x: 1710, y: 0, width: 2560, height: 1440),
                                              topInset: 0, auxiliaryTopLeftWidth: nil)

@Test func mainDisplay_isTheOneAtTheGlobalOrigin_notWhicheverHasFocus() {
    // The bug this replaces: NSScreen.main is the screen with the active window, so with no
    // key window the panel landed on whatever the user last clicked on.
    let screens = [externalSecondary, builtInPrimary]        // deliberately out of order
    #expect(NotchScreens.choose(screens, mode: .mainDisplay) == [1])
}

@Test func notchedDisplay_findsTheBuiltInPanelEvenWhenItIsNotPrimary() {
    let screens = [externalPrimary, builtInSecondary]
    #expect(NotchScreens.choose(screens, mode: .notchedDisplay) == [1])
}

@Test func notchedDisplay_fallsBackToTheMainOneWhenNoScreenHasANotch() {
    // A desktop Mac has no notch anywhere. Showing nothing at all would look like the setting
    // silently turned the panel off.
    let screens = [externalPrimary, externalSecondary]
    #expect(NotchScreens.choose(screens, mode: .notchedDisplay) == [0])
}

@Test func allDisplays_meansOnePanelEach_inScreenOrder() {
    let screens = [externalPrimary, builtInSecondary]
    #expect(NotchScreens.choose(screens, mode: .allDisplays) == [0, 1])
}

@Test func noScreensAtAll_choosesNothingRatherThanCrashing() {
    for mode in NotchDisplay.allCases {
        #expect(NotchScreens.choose([], mode: mode).isEmpty)
    }
}

@Test func withoutAScreenAtTheOrigin_theFirstOneIsUsed() {
    // Displays can be arranged so none starts at exactly (0,0) in an odd configuration;
    // picking nothing would hide the panel with no explanation.
    let odd = [ScreenMetrics(frame: CGRect(x: 100, y: 40, width: 1440, height: 900),
                             topInset: 0, auxiliaryTopLeftWidth: nil)]
    #expect(NotchScreens.choose(odd, mode: .mainDisplay) == [0])
}

@Test func aSingleNotchedLaptopGivesTheSameAnswerForEveryMode() {
    let screens = [builtInPrimary]
    #expect(NotchScreens.choose(screens, mode: .mainDisplay) == [0])
    #expect(NotchScreens.choose(screens, mode: .notchedDisplay) == [0])
    #expect(NotchScreens.choose(screens, mode: .allDisplays) == [0])
}
