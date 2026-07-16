// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    public init() {}

    public var body: some View {
        Form {
            Stepper("Default sync interval: \(defaultInterval)s", value: $defaultInterval, in: 60...3600, step: 60)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.setEnabled(on) }
        }
        .padding(20).frame(width: 360)
    }
}
