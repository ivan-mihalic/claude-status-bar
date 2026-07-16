// App/ClaudeStatusBarMain.swift
import SwiftUI
import ClaudeStatusBarApp

@main
struct ClaudeStatusBarMain: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(env: env)
        } label: {
            let level = MenuBarIndicator.level(maxUtilization: env.appState.maxUtilization)
            Image(systemName: level == .critical ? "gauge.high" : level == .warn ? "gauge.medium" : "gauge.low")
            Text(MenuBarIndicator.label(maxUtilization: env.appState.maxUtilization))
        }
        .menuBarExtraStyle(.window)

        Window("Claude Usage", id: "dashboard") { DashboardView(env: env) }
        Window("Add Account", id: "add-account") { AddAccountView(env: env) }
        Settings { SettingsView() }
    }

    init() { env.bootstrap() }
}
