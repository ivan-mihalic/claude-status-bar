// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    private let updatesButton: AnyView?
    public init(updatesButton: AnyView? = nil) {
        self.updatesButton = updatesButton
    }

    public var body: some View {
        Form {
            Stepper("Default sync interval: \(defaultInterval)s", value: $defaultInterval, in: 60...3600, step: 60)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LaunchAtLogin.setEnabled(on)
                    launchAtLogin = LaunchAtLogin.isEnabled   // revert if register/unregister failed
                }
            if let updatesButton {
                updatesButton
            }
        }
        .padding(20).frame(width: 360)
    }
}
