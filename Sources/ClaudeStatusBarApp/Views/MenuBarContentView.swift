// Sources/ClaudeStatusBarApp/Views/MenuBarContentView.swift
import SwiftUI
import AppKit

public struct MenuBarContentView: View {
    @Bindable var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                if let err = env.appState.lastError {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(err).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { env.appState.clearError() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                    Divider()
                }
                if env.appState.accounts.isEmpty {
                    Text("No accounts connected").foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    ForEach(env.appState.accounts) { acct in
                        AccountRowView(account: acct, now: ctx.date)
                        Divider()
                    }
                }
                Button("Add Account…") { openWindow(id: "add-account") }
                Button("Open Dashboard") { openWindow(id: "dashboard") }
                SettingsLink { Text("Settings…") }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 320)
        }
    }
}
