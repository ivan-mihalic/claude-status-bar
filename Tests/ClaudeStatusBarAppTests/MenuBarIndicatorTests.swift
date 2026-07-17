import Testing
@testable import ClaudeStatusBarApp

@Test func level_thresholds() {
    #expect(MenuBarIndicator.level(maxUtilization: nil) == .unknown)
    #expect(MenuBarIndicator.level(maxUtilization: 0) == .ok)
    #expect(MenuBarIndicator.level(maxUtilization: 69.9) == .ok)
    #expect(MenuBarIndicator.level(maxUtilization: 70) == .warn)
    #expect(MenuBarIndicator.level(maxUtilization: 89.9) == .warn)
    #expect(MenuBarIndicator.level(maxUtilization: 90) == .critical)
    #expect(MenuBarIndicator.level(maxUtilization: 100) == .critical)
}
@Test func label_showsDashWhenUnknown() {
    #expect(MenuBarIndicator.label(maxUtilization: nil) == "—")
    #expect(MenuBarIndicator.label(maxUtilization: 42.6) == "43%")
}
