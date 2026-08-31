// Sources/ClaudeStatusBarApp/Views/NotchSettingsView.swift
import SwiftUI

/// Everything about the notch panel, in its own screen rather than three rows buried in
/// general Settings: position and height are spatial choices people fiddle with, and the
/// preview here is the fastest way to see what a setting does without hunting for the panel
/// on screen.
public struct NotchSettingsView: View {
    @AppStorage("showNotchPanel") private var enabled = false
    @AppStorage("notchPlacement") private var placementRaw = NotchPlacement.topCenter.rawValue
    @AppStorage("notchEdgeOffsetPercent") private var edgeOffset = 50.0
    @AppStorage("notchExpandOnHover") private var expandOnHover = true
    @AppStorage("notchShowPopover") private var showPopover = true

    public init() {}

    private var placement: NotchPlacement {
        NotchPlacement(rawValue: placementRaw) ?? .topCenter
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

                Text(placement.isEdge
                     ? "On an edge the rings are always visible, small, and grow when you point at them."
                     : "At the top the panel rests inside the notch — on a Mac without one it "
                       + "appears as a pill over the middle of the menu bar, and both are "
                       + "hidden until you point at them.")
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
