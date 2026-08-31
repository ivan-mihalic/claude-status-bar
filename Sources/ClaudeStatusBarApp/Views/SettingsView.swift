// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    @AppStorage("showDockIcon") private var showDockIcon = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    public init() {}

    public var body: some View {
        Form {
            Stepper("Sync no more often than: \(defaultInterval)s",
                    value: $defaultInterval, in: 60...3600, step: 60)
            Text("A floor, not a fixed rate. An account close to a limit is checked this "
                 + "often; a quiet one is checked less, and nothing is fetched at all while "
                 + "the screen is asleep. On battery and in Low Power Mode the gaps grow.")
                .font(.caption).foregroundStyle(.secondary)
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
            Text("Each Dashboard tile carries an \"In menu bar\" switch, so a long label can be "
                 + "trimmed account by account. The notch panel has its own screen in the sidebar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 360)
    }
}
