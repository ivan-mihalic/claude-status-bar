// Sources/ClaudeStatusBarApp/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @AppStorage("menuBarShowAccountPercents") private var showAccountPercents = false
    @AppStorage("showDockIcon") private var showDockIcon = false
    @AppStorage("showNotchPanel") private var showNotchPanel = false
    @AppStorage("notchPlacement") private var notchPlacement = NotchPlacement.topCenter.rawValue
    @AppStorage("notchEdgeOffsetPercent") private var notchEdgeOffset = 50.0
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
            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, on in
                    DockController.shared.setShowDock(on)
                }
            Toggle("Show each account's percentages in the menu bar", isOn: $showAccountPercents)
            Toggle("Show usage rings in the notch", isOn: $showNotchPanel)
            if showNotchPanel {
                Picker("Panel position", selection: $notchPlacement) {
                    ForEach(NotchPlacement.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if NotchPlacement(rawValue: notchPlacement)?.isEdge == true {
                    // 0 % = top of the screen, 100 % = bottom.
                    Slider(value: $notchEdgeOffset, in: 0...100, step: 1) {
                        Text("Height on the edge")
                    } minimumValueLabel: { Text("Top").font(.caption2) }
                      maximumValueLabel: { Text("Bottom").font(.caption2) }
                }
            }
            Text("Adds a panel at the top of the screen, or against either side. On Macs "
                 + "without a notch the top position appears as a pill over the middle of the "
                 + "menu bar. The menu-bar icon stays either way.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Add a short prefix per account in the Dashboard to tell them apart.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 380)
    }
}
