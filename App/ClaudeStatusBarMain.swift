// App/ClaudeStatusBarMain.swift
import SwiftUI
import ClaudeStatusBarApp
import Sparkle

@main
struct ClaudeStatusBarMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()
    @State private var router = AppRouter()
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    private let updaterUIDelegate = UpdaterUIDelegate()
    private let updaterController: SPUStandardUpdaterController

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(env: env)
                .environment(router)
        } label: {
            let level = MenuBarIndicator.level(maxUtilization: env.appState.maxUtilization)
            Image(systemName: level == .critical ? "gauge.high" : level == .warn ? "gauge.medium" : "gauge.low")
            Text(MenuBarLabel.text(accounts: env.appState.accounts, showAccountPercents: showAccountPercents))
        }
        .menuBarExtraStyle(.window)

        // A single window (not a WindowGroup) → at most one app window ever. Its
        // sidebar switches between Dashboard / Add Account / Settings / About, so every
        // action is reachable from any screen, not just the menu-bar popover. Placed
        // after the MenuBarExtra (the primary scene) so this accessory/menu-bar app
        // doesn't auto-present it at launch — it appears only when an action opens it.
        Window("Claude Status Bar", id: "main") {
            RootView(env: env, updater: updaterController.updater)
                .environment(router)
        }
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: updaterUIDelegate)
        env.bootstrap()
    }
}
