// Sources/ClaudeStatusBarApp/Views/AddAccountView.swift
import SwiftUI
import ClaudeStatusBarCore

public struct AddAccountView: View {
    @Bindable var env: AppEnvironment
    @Environment(AppRouter.self) private var router
    @AppStorage("defaultIntervalSeconds") private var defaultInterval = 300
    @State private var provider: Provider = .claude
    @State private var pending: PendingLogin?
    @State private var code = ""
    @State private var label = ""
    @State private var error: String?
    @State private var connecting = false
    public init(env: AppEnvironment) { self.env = env }

    /// Non-nil when the router sent us here from an account's "Sign in again":
    /// the new token then replaces that account's token instead of adding a tile.
    private var reauthAccount: Account? {
        guard let id = router.reauthTarget else { return nil }
        return env.appState.accounts.first { $0.id == id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let acct = reauthAccount {
                Text("Sign in again").font(.title3.bold())
                Text("Reconnecting “\(acct.label)”. Its name, menu label, interval and "
                     + "position stay as they are — only the expired credentials are replaced.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Add an account").font(.title3.bold())
                Picker("Service", selection: $provider) {
                    ForEach(Provider.allCases) { p in
                        Text(p.isSupported ? p.title : "\(p.title) (not available)").tag(p)
                    }
                }
                .onChange(of: provider) { _, _ in pending = nil; code = ""; error = nil }
                if let why = provider.unsupportedReason {
                    Text(why).font(.caption).foregroundStyle(.secondary)
                }
                TextField("Label (email)", text: $label)
            }
            if pending == nil {
                Button("Sign in with \(provider.title)…") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!provider.isSupported || connecting)
            } else if usesPastedCode {
                Text("A browser opened. After signing in, copy the code shown on the callback page and paste it here.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Paste authorization code", text: $code)
                Button(connecting ? "Connecting…" : "Connect") { Task { await connect() } }
                    .disabled(code.isEmpty || connecting).buttonStyle(.borderedProminent)
                Button("Start over") { pending = nil; code = ""; error = nil }
            } else {
                // Codex redirects to a local address instead of showing a code, so there is
                // nothing to paste — the app is waiting for the browser to come back.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the browser to finish signing in…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel") { pending = nil; error = nil }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(20).frame(width: 380)
        .onAppear { pending = nil; code = ""; error = nil }
    }

    /// Anthropic shows the code on a web page; Codex redirects to a loopback address the app
    /// listens on. The difference is visible here and nowhere else.
    private var usesPastedCode: Bool {
        (pending?.provider ?? provider) == .claude
    }

    private func start() {
        error = nil
        let target = reauthAccount?.effectiveProvider ?? provider
        guard let started = env.accountManager.beginLogin(provider: target) else {
            error = target.unsupportedReason ?? "\(target.title) sign-in isn't available."
            return
        }
        pending = started
        // Read the provider off the pending login rather than the @State picker: for a
        // re-sign-in the picker isn't even shown, and it would still say "Claude".
        if started.provider != .claude { Task { await connect() } }
    }

    private func connect() async {
        guard let pending else { return }
        connecting = true; defer { connecting = false }
        do {
            let name = label.isEmpty ? "\(pending.provider.title) account" : label
            if let acct = reauthAccount {
                if usesPastedCode {
                    try await env.accountManager.reauth(acct.id, pending, code: code)
                } else {
                    try await env.accountManager.reauth(acct.id, pending)
                }
            } else if usesPastedCode {
                _ = try await env.accountManager.finishAdd(pending, code: code,
                        label: name, interval: defaultInterval)
            } else {
                _ = try await env.accountManager.finishAdd(pending, label: name,
                                                           interval: defaultInterval)
            }
            env.syncCoordinator.start()   // (re)start loops incl. the new/refreshed account
            self.pending = nil; code = ""; label = ""; error = nil
            router.show(.dashboard)       // back to the overview in the same window
        } catch { self.error = Redaction.redact("\(error)") }
    }
}
