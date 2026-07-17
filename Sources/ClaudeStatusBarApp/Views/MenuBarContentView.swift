// Sources/ClaudeStatusBarApp/Views/MenuBarContentView.swift
import SwiftUI
import AppKit

public struct MenuBarContentView: View {
    @Bindable var env: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    public init(env: AppEnvironment) {
        self.env = env
    }

    // An LSUIElement (accessory) app can't present or key-focus a window via
    // openWindow alone — the window silently never appears, and even if it did,
    // its text fields wouldn't accept keyboard input. Become a regular app +
    // activate first so the window shows and the paste field is typable.
    private func openAppWindow(_ id: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

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
                Button("Add Account…") { openAppWindow("add-account") }
                Button("Open Dashboard") { openAppWindow("dashboard") }
                Button("Settings…") { openAppWindow("settings") }
                Button("About…") { openAppWindow("about") }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 320)
        }
    }
}
