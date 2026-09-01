// Sources/ClaudeStatusBarApp/Views/NotchSettingsView.swift
import SwiftUI

/// Everything about the notch panel, in its own screen rather than three rows buried in
/// general Settings: position and height are spatial choices people fiddle with, and the
/// preview here is the fastest way to see what a setting does without hunting for the panel
/// on screen.
public struct NotchSettingsView: View {
    @Bindable var env: AppEnvironment
    @AppStorage("showNotchPanel") private var enabled = false
    @AppStorage("notchPlacement") private var placementRaw = NotchPlacement.topCenter.rawValue
    @AppStorage("notchEdgeOffsetPercent") private var edgeOffset = 50.0
    @AppStorage(NotchSettingsMigration.notchedKey) private var ringsOnNotchedDisplay = false
    @AppStorage(NotchSettingsMigration.plainKey) private var ringsOnPlainDisplay = false
    @AppStorage("notchDisplay") private var displayRaw = NotchDisplay.mainDisplay.rawValue
    @AppStorage("notchExpandOnHover") private var expandOnHover = true
    @AppStorage("notchShowPopover") private var showPopover = true

    public init(env: AppEnvironment) { self.env = env }

    private var placement: NotchPlacement {
        NotchPlacement(rawValue: placementRaw) ?? .topCenter
    }

    private var display: NotchDisplay { NotchDisplay(rawValue: displayRaw) ?? .mainDisplay }

    /// Whether the screen the panel is on right now has a cutout — so the two switches below
    /// can say which of them is the one in effect. `nil` when the panel is on every display
    /// and the question has no single answer.
    private var panelScreenHasNotch: Bool? {
        guard display != .allDisplays,
              let screen = NotchScreens.screens(for: display).first else { return nil }
        return NotchScreens.hasNotch(NotchGeometry.metrics(of: screen))
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Show the notch panel", isOn: $enabled)
                Text("A floating panel with one ring per account: the outer arc is the worst "
                     + "weekly limit, the inner one the current session. The menu-bar icon is "
                     + "unaffected — this is a second view of the same data.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Display") {
                Picker("Show the panel on", selection: $displayRaw) {
                    ForEach(NotchDisplay.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                .disabled(!enabled)
                Text(NotchDisplay(rawValue: displayRaw)?.detail ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Position") {
                Picker("Place the panel", selection: $placementRaw) {
                    ForEach(NotchPlacement.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                .disabled(!enabled)

                if placement.isEdge {
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(value: $edgeOffset, in: 0...100, step: 1) {
                            Text("Height on the edge")
                        } minimumValueLabel: { Text("Top").font(.caption2) }
                          maximumValueLabel: { Text("Bottom").font(.caption2) }
                        Text("\(Int(edgeOffset))% down the screen")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .disabled(!enabled)
                }

                if placement == .topCenter {
                    // Two switches rather than one: on a Mac with a cutout the resting panel
                    // can disappear into it, which is worth keeping; on a display without one
                    // it is a black pill whether or not the rings show. Working on the laptop
                    // and then plugging in a monitor used to mean toggling this by hand.
                    Text("Keep the rings visible without hovering")
                    Toggle("On the display with the notch", isOn: $ringsOnNotchedDisplay)
                        .disabled(!enabled)
                    Toggle("On a display without a notch", isOn: $ringsOnPlainDisplay)
                        .disabled(!enabled)
                    Text("Small rings sit under the panel the way they do on an edge. On a Mac "
                         + "with a real notch they start below the cutout, because nothing is "
                         + "visible behind it; on an external display they sit at the top. "
                         + "Whichever screen the panel lands on picks its own answer, so "
                         + "connecting a display switches this on its own.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let hasNotch = panelScreenHasNotch {
                        Text(hasNotch
                             ? "Right now the panel is on the display with the notch."
                             : "Right now the panel is on a display without a notch.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Text(placement.isEdge
                     ? "On an edge the rings are always visible, small, and grow when you point at them."
                     : "At the top the panel rests inside the notch — on a Mac without one it "
                       + "appears as a pill over the middle of the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Accounts in the panel") {
                if env.appState.accounts.isEmpty {
                    Text("No accounts yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(env.appState.accounts) { account in
                        Toggle(isOn: Binding(
                            get: { account.isShownInNotch },
                            set: { env.accountManager.setShownInNotch(account.id, $0) })
                        ) {
                            HStack(spacing: 8) {
                                ProviderMarkView(provider: account.effectiveProvider,
                                                 diameter: 16)
                                Text(account.label)
                                if let prefix = account.menuBarPrefix, !prefix.isEmpty {
                                    Text(prefix)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(.quaternary))
                                }
                            }
                        }
                        .disabled(!enabled)
                    }
                }
                Text("Hiding an account only removes its ring — it keeps syncing and still "
                     + "counts towards the menu-bar icon.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Expand when the pointer is over it", isOn: $expandOnHover)
                    .disabled(!enabled)
                Toggle("Show account details on a ring", isOn: $showPopover)
                    .disabled(!enabled || !expandOnHover)
                Text("Details open beside the ring you point at: every limit window with its "
                     + "own bar, percentage and reset time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
