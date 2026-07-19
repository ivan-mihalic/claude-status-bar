// Sources/ClaudeStatusBarApp/Views/DashboardView.swift
import SwiftUI
import AppKit
import ClaudeStatusBarCore

public struct DashboardView: View {
    @Bindable var env: AppEnvironment
    @Environment(AppRouter.self) private var router
    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        // 60s cadence: reset countdowns and "Synced N min ago" are minute-granular.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(env.appState.accounts) { acct in
                        VStack(alignment: .leading, spacing: 8) {
                            AccountRowView(account: acct, now: ctx.date,
                                           onManualSync: { await env.syncCoordinator.syncNow(acct.id) })
                            AccountEditFields(account: acct, manager: env.accountManager)
                            HStack {
                                Stepper("Every \(acct.syncInterval)s",
                                        value: Binding(
                                            get: { acct.syncInterval },
                                            set: { env.accountManager.setInterval(acct.id, seconds: max(60, $0)) }),
                                        in: 60...3600, step: 60)
                                    .font(.caption)
                                Spacer()
                                if acct.status == .needsReauth {
                                    Button("Sign in again") { router.selection = .addAccount }
                                }
                                Button(role: .destructive) {
                                    env.accountManager.remove(acct.id)
                                    env.syncCoordinator.cancel(acct.id)
                                }
                                    label: { Image(systemName: "trash") }
                            }
                        }
                        .padding().background(.quaternary.opacity(0.3)).cornerRadius(12)
                    }
                }.padding()
            }
            .frame(minWidth: 700, minHeight: 420)
            .navigationTitle("Claude Usage")
        }
    }
}

/// Editable account name + menu-bar prefix. Uses local @State so typing stays smooth
/// (no cursor jumps) and commits live to the manager as the value changes.
private struct AccountEditFields: View {
    let account: Account
    let manager: AccountManager
    @State private var name: String
    @State private var prefix: String

    init(account: Account, manager: AccountManager) {
        self.account = account
        self.manager = manager
        _name = State(initialValue: account.label)
        _prefix = State(initialValue: account.menuBarPrefix ?? "")
    }

    var body: some View {
        HStack {
            Text("Name").font(.caption).foregroundStyle(.secondary)
            TextField("account name", text: $name)
                .textFieldStyle(.roundedBorder).font(.caption)
                .onChange(of: name) { _, new in manager.setLabel(account.id, new) }
            Text("Menu label").font(.caption).foregroundStyle(.secondary)
            TextField("prefix", text: $prefix)
                .textFieldStyle(.roundedBorder).font(.caption).frame(width: 90)
                .onChange(of: prefix) { _, new in manager.setPrefix(account.id, new) }
        }
    }
}
