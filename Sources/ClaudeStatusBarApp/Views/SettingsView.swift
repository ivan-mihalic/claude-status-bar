// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    public init() {}

    public var body: some View {
        Form {
            Stepper("Default sync interval: \(defaultInterval)s", value: $defaultInterval, in: 60...3600, step: 60)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LaunchAtLogin.setEnabled(on)
                    launchAtLogin = LaunchAtLogin.isEnabled   // revert if register/unregister failed
                }
            Toggle("Show each account's percentages in the menu bar", isOn: $showAccountPercents)
            Text("Add a short prefix per account in the Dashboard to tell them apart.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 360)
    }
}
