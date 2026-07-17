// App/ClaudeStatusBarMain.swift
import SwiftUI
import ClaudeStatusBarApp
import Sparkle

@main
struct ClaudeStatusBarMain: App {
    @State private var env = AppEnvironment()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                env: env,
                updatesButton: AnyView(CheckForUpdatesView(updater: updaterController.updater)))
        } label: {
            let level = MenuBarIndicator.level(maxUtilization: env.appState.maxUtilization)
            Image(systemName: level == .critical ? "gauge.high" : level == .warn ? "gauge.medium" : "gauge.low")
            Text(MenuBarIndicator.label(maxUtilization: env.appState.maxUtilization))
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "dashboard") { DashboardView(env: env) }
        Window("Add Account", id: "add-account") { AddAccountView(env: env) }
        Settings {
            SettingsView(updatesButton: AnyView(CheckForUpdatesView(updater: updaterController.updater)))
        }
    }

    init() { env.bootstrap() }
}
