// Sources/ClaudeStatusBarApp/Views/MenuBarContentView.swift
import SwiftUI
import AppKit

public struct MenuBarContentView: View {
    @Bindable var env: AppEnvironment
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    public init(env: AppEnvironment) {
        self.env = env
    }

    // An LSUIElement (accessory) app can't present or key-focus a window via
    // openWindow alone — the window silently never appears, and even if it did,
    // its text fields wouldn't accept keyboard input. Become a regular app +
    // activate first so the window shows and the paste field is typable.
    // Every action targets the one "main" window and just picks its section.
    private func open(_ section: AppRouter.Section) {
        router.selection = section
        DockController.shared.prepareToShowWindow()
        openWindow(id: "main")
    }

    public var body: some View {
        // 60s cadence: every relative time shown here (reset countdowns, "Synced N min
        // ago") is minute-granular, so a per-second tick only wasted re-renders.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
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
                        AccountRowView(account: acct, now: ctx.date,
                                       onManualSync: { await env.syncCoordinator.syncNow(acct.id) })
                        Divider()
                    }
                }
                Button("Open Dashboard") { open(.dashboard) }
                Button("Add Account…") { open(.addAccount) }
                Button("Settings…") { open(.settings) }
                Button("About…") { open(.about) }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 320)
        }
    }
}
