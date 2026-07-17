// App/ClaudeStatusBarMain.swift
import SwiftUI
import ClaudeStatusBarApp
import Sparkle

@main
struct ClaudeStatusBarMain: App {
    @State private var env = AppEnvironment()
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    private let updaterUIDelegate = UpdaterUIDelegate()
    private let updaterController: SPUStandardUpdaterController

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                env: env,
                updatesButton: AnyView(CheckForUpdatesView(updater: updaterController.updater)))
        } label: {
            let level = MenuBarIndicator.level(maxUtilization: env.appState.maxUtilization)
            Image(systemName: level == .critical ? "gauge.high" : level == .warn ? "gauge.medium" : "gauge.low")
            Text(MenuBarLabel.text(accounts: env.appState.accounts, showAccountPercents: showAccountPercents))
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "dashboard") { DashboardView(env: env) }
        Window("Add Account", id: "add-account") { AddAccountView(env: env) }
        // A plain Window (not the Settings scene) so it opens reliably from the menu-bar
        // popover via the same activate-then-openWindow path as the other windows.
        Window("Settings", id: "settings") {
            SettingsView(updatesButton: AnyView(CheckForUpdatesView(updater: updaterController.updater)))
        }
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: updaterUIDelegate)
        env.bootstrap()
    }
}
