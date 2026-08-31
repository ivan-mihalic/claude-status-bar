// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @Bindable var env: AppEnvironment
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    @AppStorage("showDockIcon") private var showDockIcon = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        Form {
            Stepper("Default sync interval: \(defaultInterval)s", value: $defaultInterval, in: 60...3600, step: 60)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LaunchAtLogin.setEnabled(on)
                    launchAtLogin = LaunchAtLogin.isEnabled   // revert if register/unregister failed
                }
            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, on in
                    DockController.shared.setShowDock(on)
                }
            Toggle("Show each account's percentages in the menu bar", isOn: $showAccountPercents)
            Text("The notch panel has its own screen in the sidebar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 360)
    }
}
